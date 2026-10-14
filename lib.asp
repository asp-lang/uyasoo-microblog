<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
Dim db
Dim crypto
Dim currentUserId
Dim ajaxPayload
Dim ajaxStatus

ajaxPayload = ""
ajaxStatus = ""

Function RedisKey(name)
    RedisKey = REDIS_PREFIX & name
End Function

Function UserKey(userId)
    UserKey = RedisKey("user:" & CStr(userId))
End Function

Function UsernameKey(username)
    UsernameKey = RedisKey("username:" & LCase(Trim(username)))
End Function

Function NormalizeEmail(email)
    NormalizeEmail = LCase(Trim(email))
End Function

Function EmailKey(email)
    EmailKey = RedisKey("email:" & crypto.SHA256(NormalizeEmail(email)))
End Function

Function PostKey(postId)
    PostKey = RedisKey("post:" & CStr(postId))
End Function

Function CommentKey(commentId)
    CommentKey = RedisKey("comment:" & CStr(commentId))
End Function

Function FormValue(name)
    FormValue = Trim(CStr(Request.Form(name)))
End Function

Function QueryValue(name)
    QueryValue = Trim(CStr(Request.QueryString(name)))
End Function

Function ValueOrEmpty(value)
    If IsNull(value) Or IsEmpty(value) Then
        ValueOrEmpty = ""
    Else
        ValueOrEmpty = CStr(value)
    End If
End Function

Function RememberTokenKey(token)
    RememberTokenKey = RedisKey("remember:" & crypto.SHA256(token))
End Function

Function ValidRememberToken(token)
    Dim expression
    Set expression = New RegExp
    expression.Pattern = "^[a-f0-9]{64}$"
    expression.IgnoreCase = True
    ValidRememberToken = expression.Test(token)
End Function

Function ValidRememberKey(key)
    Dim prefix
    prefix = RedisKey("remember:")
    ValidRememberKey = Len(key) = Len(prefix) + 64 And Left(key, Len(prefix)) = prefix
End Function

Function RememberCookieHeader(value, maxAge)
    Dim header
    header = REMEMBER_COOKIE_NAME & "=" & value & "; Path=/; Max-Age=" & CStr(maxAge) & "; HttpOnly; SameSite=Lax"
    If LCase(ValueOrEmpty(Request.ServerVariables("HTTPS"))) = "on" Then header = header & "; Secure"
    RememberCookieHeader = header
End Function

Sub IssueRememberLogin(userId)
    Dim previousToken
    Dim previousKey
    Dim token
    Dim tokenKey
    previousKey = ValueOrEmpty(Session("remember_token_key"))
    If ValidRememberKey(previousKey) Then Call db.Del(previousKey)
    previousToken = ValueOrEmpty(Request.Cookies(REMEMBER_COOKIE_NAME))
    If ValidRememberToken(previousToken) Then Call db.Del(RememberTokenKey(previousToken))
    token = crypto.RandomHex(32)
    tokenKey = RememberTokenKey(token)
    Call db.SetEx(tokenKey, CStr(userId), REMEMBER_LOGIN_SECONDS)
    Session("remember_token_key") = tokenKey
    Response.AddHeader "Set-Cookie", RememberCookieHeader(token, REMEMBER_LOGIN_SECONDS)
End Sub

Sub ClearRememberLogin()
    Dim token
    Dim tokenKey
    tokenKey = ValueOrEmpty(Session("remember_token_key"))
    If ValidRememberKey(tokenKey) Then Call db.Del(tokenKey)
    Session.Contents.Remove "remember_token_key"
    token = ValueOrEmpty(Request.Cookies(REMEMBER_COOKIE_NAME))
    If ValidRememberToken(token) Then Call db.Del(RememberTokenKey(token))
    Response.AddHeader "Set-Cookie", RememberCookieHeader("", 0)
End Sub

Function ResolveCurrentUser()
    Dim userId
    Dim token
    userId = ValueOrEmpty(Session("user_id"))
    If userId <> "" And UserExists(userId) Then
        currentUserId = userId
        ResolveCurrentUser = userId
        Exit Function
    End If
    If userId <> "" Then Session.Contents.Remove "user_id"

    token = ValueOrEmpty(Request.Cookies(REMEMBER_COOKIE_NAME))
    If Not ValidRememberToken(token) Then
        If token <> "" Then Call ClearRememberLogin()
        currentUserId = ""
        ResolveCurrentUser = ""
        Exit Function
    End If

    userId = ValueOrEmpty(db.Get(RememberTokenKey(token)))
    If userId = "" Or Not UserExists(userId) Then
        Call ClearRememberLogin()
        currentUserId = ""
        ResolveCurrentUser = ""
        Exit Function
    End If

    Session("user_id") = userId
    currentUserId = userId
    Call IssueRememberLogin(userId)
    ResolveCurrentUser = userId
End Function

Function Html(value)
    Html = Server.HTMLEncode(ValueOrEmpty(value))
End Function

Function Url(value)
    Url = Server.URLEncode(ValueOrEmpty(value))
End Function

Function TextWithBreaks(value)
    TextWithBreaks = Replace(Html(value), vbCrLf, "<br>")
End Function

Function TopicPath(topic)
    TopicPath = APP_BASE_PATH & "?view=topic&name=" & Url(LCase(Trim(topic)))
End Function

Function TopicExpression()
    Dim expression
    Set expression = New RegExp
    expression.Pattern = "#([^#\r\n]{1," & MAX_TOPIC_LENGTH & "})#"
    expression.Global = True
    Set TopicExpression = expression
End Function

Function TextWithTopics(value)
    Dim text
    Dim expression
    Dim matches
    Dim match
    Dim topic
    Dim cursor
    Dim startAt
    Dim result
    Dim index
    text = ValueOrEmpty(value)
    Set expression = TopicExpression()
    Set matches = expression.Execute(text)
    cursor = 1
    result = ""
    For index = 0 To matches.Count - 1
        Set match = matches.Item(index)
        startAt = match.FirstIndex + 1
        result = result & TextWithBreaks(Mid(text, cursor, startAt - cursor))
        topic = Trim(CStr(match.SubMatches(0)))
        If topic = "" Then
            result = result & Html(match.Value)
        Else
            result = result & "<a class=""topic-link"" href=""" & TopicPath(topic) & """>#" & Html(topic) & "#</a>"
        End If
        cursor = startAt + match.Length
    Next
    result = result & TextWithBreaks(Mid(text, cursor))
    TextWithTopics = result
End Function

Sub IndexPostTopics(postId, body)
    Dim expression
    Dim matches
    Dim match
    Dim topic
    Dim normalized
    Dim added
    Dim index
    Set expression = TopicExpression()
    Set matches = expression.Execute(body)
    For index = 0 To matches.Count - 1
        Set match = matches.Item(index)
        topic = Trim(CStr(match.SubMatches(0)))
        normalized = LCase(topic)
        If topic <> "" Then
            added = db.SAdd(RedisKey("post:" & postId & ":topics"), normalized)
            If CLng(added) = 1 Then
                Call db.HSet(RedisKey("topic:names"), normalized, topic)
                Call db.LPush(RedisKey("topic:" & normalized & ":posts"), postId)
                Call db.Execute("ZINCRBY", RedisKey("topics:counts"), "1", normalized)
            End If
        End If
    Next
End Sub

Sub RemovePostTopics(postId)
    Dim topics
    Dim topic
    Dim score
    topics = db.SMembers(RedisKey("post:" & postId & ":topics"))
    If IsArray(topics) Then
        For Each topic In topics
            Call db.Execute("LREM", RedisKey("topic:" & topic & ":posts"), "0", postId)
            score = CDbl(db.Execute("ZINCRBY", RedisKey("topics:counts"), "-1", topic))
            If score <= 0 Then
                Call db.Execute("ZREM", RedisKey("topics:counts"), topic)
                Call db.Execute("HDEL", RedisKey("topic:names"), topic)
                Call db.Del(RedisKey("topic:" & topic & ":posts"))
            End If
        Next
    End If
    Call db.Del(RedisKey("post:" & postId & ":topics"))
End Sub

Function Timestamp()
    Dim value
    value = Now()
    Timestamp = Year(value) & "-" & Right("0" & Month(value), 2) & "-" & _
        Right("0" & Day(value), 2) & " " & Right("0" & Hour(value), 2) & ":" & _
        Right("0" & Minute(value), 2)
End Function

Function CurrentPath(viewName)
    If viewName = "" Or viewName = "home" Then
        CurrentPath = APP_BASE_PATH
    Else
        CurrentPath = APP_BASE_PATH & "?view=" & Url(viewName)
    End If
End Function

Function ProfilePath(userId)
    ProfilePath = APP_BASE_PATH & "?view=profile&id=" & Url(userId)
End Function

Function IsPost()
    IsPost = UCase(Request.ServerVariables("request_method")) = "POST"
End Function

Function IsAjaxRequest()
    Dim requestedWith
    Dim accept
    requestedWith = LCase(ValueOrEmpty(Request.ServerVariables("HTTP_X_REQUESTED_WITH")))
    accept = LCase(ValueOrEmpty(Request.ServerVariables("HTTP_ACCEPT")))
    IsAjaxRequest = requestedWith = "xmlhttprequest" Or InStr(1, accept, "application/json", 0) > 0 Or QueryValue("_ajax") = "1"
End Function

Function AjaxJsonString(value)
    Dim text
    text = ValueOrEmpty(value)
    text = Replace(text, "\", "\\")
    text = Replace(text, Chr(34), "\" & Chr(34))
    text = Replace(text, vbCrLf, "\n")
    text = Replace(text, vbCr, "\n")
    text = Replace(text, vbLf, "\n")
    text = Replace(text, Chr(8), "\b")
    text = Replace(text, Chr(9), "\t")
    AjaxJsonString = Chr(34) & text & Chr(34)
End Function

Sub AddAjaxValue(name, value)
    ajaxPayload = ajaxPayload & "," & AjaxJsonString(name) & ":" & AjaxJsonString(value)
End Sub

Sub WriteAjaxResponse(ok, message, location)
    Response.ContentType = "application/json"
    Response.AddHeader "Cache-Control", "no-store"
    Response.AddHeader "X-Content-Type-Options", "nosniff"
    If ajaxStatus <> "" Then Response.Status = ajaxStatus
    Response.Write "{""ok"":"
    If ok Then
        Response.Write "true"
    Else
        Response.Write "false"
    End If
    Response.Write ",""message"":" & AjaxJsonString(message)
    Response.Write ",""redirect"":" & AjaxJsonString(location) & ajaxPayload & "}"
    Response.End
End Sub

Function UserField(userId, field)
    UserField = ValueOrEmpty(db.HGet(UserKey(userId), field))
End Function

Function UserExists(userId)
    UserExists = False
    If CStr(userId) <> "" Then
        UserExists = CLng(db.Exists(UserKey(userId))) = 1
    End If
End Function

Function UserDisplayName(userId)
    Dim value
    value = UserField(userId, "display_name")
    If value = "" Then value = UserField(userId, "username")
    UserDisplayName = value
End Function

Function UserInitial(userId)
    Dim value
    value = UserDisplayName(userId)
    If value = "" Then
        UserInitial = "?"
    Else
        UserInitial = UCase(Left(value, 1))
    End If
End Function

Function DefaultAvatarPath(index)
    DefaultAvatarPath = "assets/avatars/avatar-" & Right("0" & CStr(index), 2) & ".jpg"
End Function

Function IsDefaultAvatar(path)
    Dim index
    IsDefaultAvatar = False
    For index = 1 To DEFAULT_AVATAR_COUNT
        If path = DefaultAvatarPath(index) Then
            IsDefaultAvatar = True
            Exit Function
        End If
    Next
End Function

Function AvatarPath(userId)
    Dim path
    path = UserField(userId, "avatar")
    If path = "" Then path = DefaultAvatarPath(((CLng(userId) - 1) Mod DEFAULT_AVATAR_COUNT) + 1)
    AvatarPath = path
End Function

Function IsUploadedImagePath(path)
    Dim expression
    Set expression = New RegExp
    expression.Pattern = "^assets/uploads/(user|post)-[0-9]+-[a-f0-9]{32}\.(jpg|png|webp)$"
    expression.IgnoreCase = True
    IsUploadedImagePath = expression.Test(ValueOrEmpty(path))
End Function

Function UploadedImageCacheKey(path)
    UploadedImageCacheKey = RedisKey("image-cache:" & crypto.SHA256(LCase(ValueOrEmpty(path))))
End Function

Function ImageUrl(path)
    Dim value
    value = ValueOrEmpty(path)
    If IsUploadedImagePath(value) Then
        ImageUrl = "image.asp?name=" & Url(Mid(value, Len("assets/uploads/") + 1))
    Else
        ImageUrl = value
    End If
End Function

Sub CacheUploadedImage(path, data)
    If Not IsUploadedImagePath(path) Or IsEmpty(data) Or LenB(data) = 0 Then Exit Sub
    Call db.SetEx(UploadedImageCacheKey(path), data, IMAGE_CACHE_SECONDS)
End Sub

Function SetCount(key)
    SetCount = CLng(db.Execute("SCARD", key))
End Function

Function ListCount(key)
    ListCount = CLng(db.Execute("LLEN", key))
End Function

Function CurrentPostSequence()
    Dim value
    value = ValueOrEmpty(db.Get(RedisKey("next:post")))
    If IsNumeric(value) Then
        CurrentPostSequence = CLng(value)
    Else
        CurrentPostSequence = 0
    End If
End Function

Function IsFollowing(viewerId, targetId)
    IsFollowing = False
    If viewerId <> "" And targetId <> "" Then
        IsFollowing = CLng(db.Execute("SISMEMBER", RedisKey("following:" & viewerId), targetId)) = 1
    End If
End Function

Function IsLiked(postId, userId)
    IsLiked = False
    If userId <> "" Then
        IsLiked = CLng(db.Execute("SISMEMBER", RedisKey("post:" & postId & ":likes"), userId)) = 1
    End If
End Function

Function ValidUsername(username)
    Dim expression
    Set expression = New RegExp
    expression.Pattern = "^[A-Za-z0-9_]{3,20}$"
    ValidUsername = expression.Test(username)
End Function

Function ValidEmail(email)
    Dim atPosition
    Dim localPart
    Dim domainPart
    Dim labels
    Dim label
    Dim expression
    email = NormalizeEmail(email)
    ValidEmail = False
    If Len(email) < 3 Or Len(email) > MAX_EMAIL_LENGTH Then Exit Function
    atPosition = InStr(1, email, "@", 0)
    If atPosition <= 1 Or atPosition <> InStrRev(email, "@", -1, 0) Or atPosition >= Len(email) Then Exit Function
    localPart = Left(email, atPosition - 1)
    domainPart = Mid(email, atPosition + 1)
    If Len(localPart) > MAX_EMAIL_LOCAL_LENGTH Then Exit Function
    If Left(localPart, 1) = "." Or Right(localPart, 1) = "." Or InStr(1, localPart, "..", 0) > 0 Then Exit Function

    Set expression = New RegExp
    expression.Pattern = "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$"
    expression.IgnoreCase = True
    If Not expression.Test(localPart) Then Exit Function

    labels = Split(domainPart, ".")
    If UBound(labels) < 1 Then Exit Function
    expression.Pattern = "^[a-z0-9-]+$"
    For Each label In labels
        If Len(label) < 1 Or Len(label) > 63 Then Exit Function
        If Left(label, 1) = "-" Or Right(label, 1) = "-" Then Exit Function
        If Not expression.Test(label) Then Exit Function
    Next
    ValidEmail = True
End Function

Function ValidPostLink(linkUrl)
    Dim expression
    ValidPostLink = False
    If Len(linkUrl) < 1 Or Len(linkUrl) > MAX_POST_LINK_LENGTH Then Exit Function
    Set expression = New RegExp
    expression.Pattern = "^https?://[^ \t\r\n]+$"
    expression.IgnoreCase = True
    ValidPostLink = expression.Test(linkUrl)
End Function

Function HashPassword(password, salt)
    Dim digest
    Dim index
    digest = salt & ":" & password
    For index = 1 To PASSWORD_HASH_ROUNDS
        digest = crypto.SHA256(digest)
    Next
    HashPassword = digest
End Function

Function CsrfToken()
    If IsEmpty(Session("csrf_token")) Or Session("csrf_token") = "" Then
        Session("csrf_token") = crypto.RandomHex(24)
    End If
    CsrfToken = CStr(Session("csrf_token"))
End Function

Function ValidCsrf()
    ValidCsrf = False
    If Not IsEmpty(Session("csrf_token")) Then
        ValidCsrf = crypto.ConstantTimeEquals(CStr(Session("csrf_token")), FormValue("csrf"))
    End If
End Function

Sub SetFlash(kind, message)
    Session("flash_kind") = kind
    Session("flash_message") = message
End Sub

Sub RenderFlash()
    Dim kind
    Dim message
    If IsEmpty(Session("flash_message")) Then Exit Sub
    kind = ValueOrEmpty(Session("flash_kind"))
    message = ValueOrEmpty(Session("flash_message"))
    Session.Contents.Remove "flash_kind"
    Session.Contents.Remove "flash_message"
    Response.Write "<div class=""flash flash-" & Html(kind) & """ role=""status"">" & Html(message) & "</div>"
End Sub

Sub RedirectTo(location)
    Dim kind
    Dim message
    If IsAjaxRequest() Then
        kind = ValueOrEmpty(Session("flash_kind"))
        message = ValueOrEmpty(Session("flash_message"))
        Session.Contents.Remove "flash_kind"
        Session.Contents.Remove "flash_message"
        If kind = "error" And ajaxStatus = "" Then ajaxStatus = "422 Unprocessable Entity"
        Call WriteAjaxResponse(kind <> "error", message, location)
    End If
    Response.Redirect location
    Response.End
End Sub

Sub RequireAuth()
    If currentUserId = "" Then
        ajaxStatus = "401 Unauthorized"
        Call SetFlash("error", "Sign in to continue.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
End Sub

Sub RequireCsrf()
    If Not ValidCsrf() Then
        Response.Status = "403 Forbidden"
        If IsAjaxRequest() Then
            ajaxStatus = "403 Forbidden"
            Call WriteAjaxResponse(False, "Invalid or expired form token.", APP_BASE_PATH)
        End If
        Response.ContentType = "text/plain"
        Response.Write "Invalid or expired form token."
        Response.End
    End If
End Sub

Sub HandleRegister()
    Dim username
    Dim displayName
    Dim email
    Dim password
    Dim userId
    Dim salt
    Dim claimed
    Dim emailClaimed
    Dim captcha
    Dim expectedCaptcha
    username = FormValue("username")
    displayName = FormValue("display_name")
    email = NormalizeEmail(FormValue("email"))
    password = FormValue("password")
    captcha = UCase(FormValue("captcha"))
    expectedCaptcha = ""
    If Not IsEmpty(Session("register_captcha")) Then expectedCaptcha = UCase(CStr(Session("register_captcha")))
    Session.Contents.Remove "register_captcha"
    If captcha = "" Or expectedCaptcha = "" Or Not crypto.ConstantTimeEquals(expectedCaptcha, captcha) Then
        Call SetFlash("error", "The verification code is incorrect or expired.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    If Not ValidUsername(username) Then
        Call SetFlash("error", "Username must be 3-20 letters, numbers, or underscores.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    If Len(displayName) < 1 Or Len(displayName) > 40 Then
        Call SetFlash("error", "Display name must be between 1 and 40 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    If Not ValidEmail(email) Then
        Call SetFlash("error", "Enter a valid email address.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    If Len(password) < 8 Or Len(password) > 128 Then
        Call SetFlash("error", "Password must be between 8 and 128 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    userId = CStr(db.Incr(RedisKey("next:user")))
    claimed = db.Execute("SET", UsernameKey(username), userId, "NX")
    If IsNull(claimed) Then
        Call SetFlash("error", "That username is already registered.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    emailClaimed = db.Execute("SET", EmailKey(email), userId, "NX")
    If IsNull(emailClaimed) Then
        Call db.Del(UsernameKey(username))
        Call SetFlash("error", "That email address is already registered.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    salt = crypto.RandomHex(16)
    Call db.HSet(UserKey(userId), "username", username)
    Call db.HSet(UserKey(userId), "display_name", displayName)
    Call db.HSet(UserKey(userId), "email", email)
    Call db.HSet(UserKey(userId), "password_salt", salt)
    Call db.HSet(UserKey(userId), "password_hash", HashPassword(password, salt))
    Call db.HSet(UserKey(userId), "bio", "")
    Call db.HSet(UserKey(userId), "avatar", DefaultAvatarPath(((CLng(userId) - 1) Mod DEFAULT_AVATAR_COUNT) + 1))
    Call db.HSet(UserKey(userId), "created_at", Timestamp())
    Call db.SAdd(RedisKey("users"), userId)
    Session("user_id") = userId
    currentUserId = userId
    Call IssueRememberLogin(userId)
    Call SetFlash("success", "Your account is ready.")
    Call RedirectTo(APP_BASE_PATH)
End Sub

Sub HandleLogin()
    Dim username
    Dim password
    Dim userId
    Dim salt
    username = FormValue("username")
    password = FormValue("password")
    userId = ValueOrEmpty(db.Get(UsernameKey(username)))
    If userId = "" Then
        Call SetFlash("error", "The username or password is incorrect.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    salt = UserField(userId, "password_salt")
    If Not crypto.ConstantTimeEquals(UserField(userId, "password_hash"), HashPassword(password, salt)) Then
        Call SetFlash("error", "The username or password is incorrect.")
        Call RedirectTo(APP_BASE_PATH & "?view=auth")
    End If
    Session("user_id") = userId
    currentUserId = userId
    Call IssueRememberLogin(userId)
    Call SetFlash("success", "Welcome back, " & UserDisplayName(userId) & ".")
    Call RedirectTo(APP_BASE_PATH)
End Sub

Sub HandleLogout()
    Call ClearRememberLogin()
    Session.Contents.Remove "user_id"
    currentUserId = ""
    Call SetFlash("success", "You are signed out.")
    Call RedirectTo(APP_BASE_PATH & "?view=auth")
End Sub

Sub HandlePublish()
    Dim body
    Dim postId
    Call RequireAuth()
    body = FormValue("body")
    If Len(body) < 1 Or Len(body) > MAX_POST_LENGTH Then
        Call SetFlash("error", "Posts must contain 1-280 characters.")
        Call RedirectTo(APP_BASE_PATH)
    End If
    postId = StorePost(body, "", "", "")
    Call AddAjaxValue("post_id", postId)
    Call SetFlash("success", "Your post is live.")
    Call RedirectTo(APP_BASE_PATH)
End Sub

Function StorePost(body, imagePath, linkUrl, linkLabel)
    Dim postId
    postId = CStr(db.Incr(RedisKey("next:post")))
    Call db.HSet(PostKey(postId), "author_id", currentUserId)
    Call db.HSet(PostKey(postId), "body", body)
    Call db.HSet(PostKey(postId), "created_at", Timestamp())
    If imagePath <> "" Then Call db.HSet(PostKey(postId), "image", imagePath)
    If linkUrl <> "" Then
        Call db.HSet(PostKey(postId), "link_url", linkUrl)
        Call db.HSet(PostKey(postId), "link_label", linkLabel)
    End If
    Call db.LPush(RedisKey("posts:global"), postId)
    Call db.LPush(RedisKey("user:" & currentUserId & ":posts"), postId)
    Call IndexPostTopics(postId, body)
    StorePost = postId
End Function

Sub DeletePostImage(imagePath)
    Dim fileSystem
    If imagePath = "" Then Exit Sub
    If Not IsUploadedImagePath(imagePath) Or InStr(1, imagePath, "assets/uploads/post-", 1) <> 1 Then Exit Sub
    Call db.Del(UploadedImageCacheKey(imagePath))
    Set fileSystem = Server.CreateObject("Scripting.FileSystemObject")
    If fileSystem.FileExists(Server.MapPath(imagePath)) Then fileSystem.DeleteFile Server.MapPath(imagePath), True
    Set fileSystem = Nothing
End Sub

Sub HandleDeletePost()
    Dim postId
    Dim authorId
    Dim imagePath
    Dim comments
    Dim commentId
    Call RequireAuth()
    postId = FormValue("post_id")
    authorId = UserFieldFromPost(postId, "author_id")
    If authorId <> currentUserId Then
        Response.Status = "403 Forbidden"
        If IsAjaxRequest() Then
            ajaxStatus = "403 Forbidden"
            Call WriteAjaxResponse(False, "You cannot delete this post.", APP_BASE_PATH)
        End If
        Response.Write "You cannot delete this post."
        Response.End
    End If
    imagePath = UserFieldFromPost(postId, "image")
    comments = db.LRange(RedisKey("post:" & postId & ":comments"), 0, -1)
    If IsArray(comments) Then
        For Each commentId In comments
            Call db.Del(CommentKey(commentId))
        Next
    End If
    Call RemovePostTopics(postId)
    Call db.Execute("MULTI")
    Call db.Execute("LREM", RedisKey("posts:global"), "0", postId)
    Call db.Execute("LREM", RedisKey("user:" & currentUserId & ":posts"), "0", postId)
    Call db.Del(PostKey(postId), RedisKey("post:" & postId & ":likes"), RedisKey("post:" & postId & ":comments"))
    Call db.Execute("EXEC")
    Call DeletePostImage(imagePath)
    Call AddAjaxValue("post_id", postId)
    Call SetFlash("success", "Post deleted.")
    Call RedirectTo(APP_BASE_PATH)
End Sub

Sub HandleFollow(shouldFollow)
    Dim targetId
    Dim targetName
    Call RequireAuth()
    targetId = FormValue("target_id")
    If targetId = currentUserId Or Not UserExists(targetId) Then
        Call SetFlash("error", "That account cannot be followed.")
        Call RedirectTo(APP_BASE_PATH)
    End If
    targetName = UserDisplayName(targetId)
    Call db.Execute("MULTI")
    If shouldFollow Then
        Call db.SAdd(RedisKey("following:" & currentUserId), targetId)
        Call db.SAdd(RedisKey("followers:" & targetId), currentUserId)
        Call SetFlash("success", "You are now following " & targetName & ".")
    Else
        Call db.Execute("SREM", RedisKey("following:" & currentUserId), targetId)
        Call db.Execute("SREM", RedisKey("followers:" & targetId), currentUserId)
        Call SetFlash("success", "You unfollowed " & targetName & ".")
    End If
    Call db.Execute("EXEC")
    Call AddAjaxValue("target_id", targetId)
    Call AddAjaxValue("following", CStr(shouldFollow))
    Call AddAjaxValue("follower_count", CStr(SetCount(RedisKey("followers:" & targetId))))
    Call AddAjaxValue("following_count", CStr(SetCount(RedisKey("following:" & currentUserId))))
    Call RedirectTo(ProfilePath(targetId))
End Sub

Sub HandleLike(shouldLike)
    Dim postId
    Call RequireAuth()
    postId = FormValue("post_id")
    If CLng(db.Exists(PostKey(postId))) <> 1 Then
        Call SetFlash("error", "That post no longer exists.")
        Call RedirectTo(APP_BASE_PATH)
    End If
    If shouldLike Then
        Call db.SAdd(RedisKey("post:" & postId & ":likes"), currentUserId)
    Else
        Call db.Execute("SREM", RedisKey("post:" & postId & ":likes"), currentUserId)
    End If
    Call AddAjaxValue("post_id", postId)
    Call RedirectTo(APP_BASE_PATH & "?view=post&id=" & Url(postId))
End Sub

Sub HandleComment()
    Dim postId
    Dim body
    Dim commentId
    Call RequireAuth()
    postId = FormValue("post_id")
    body = FormValue("body")
    If CLng(db.Exists(PostKey(postId))) <> 1 Then
        Call SetFlash("error", "That post no longer exists.")
        Call RedirectTo(APP_BASE_PATH)
    End If
    If Len(body) < 1 Or Len(body) > MAX_COMMENT_LENGTH Then
        Call SetFlash("error", "Comments must contain 1-160 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=post&id=" & Url(postId))
    End If
    commentId = CStr(db.Incr(RedisKey("next:comment")))
    Call db.HSet(CommentKey(commentId), "author_id", currentUserId)
    Call db.HSet(CommentKey(commentId), "body", body)
    Call db.HSet(CommentKey(commentId), "created_at", Timestamp())
    Call db.RPush(RedisKey("post:" & postId & ":comments"), commentId)
    Call AddAjaxValue("post_id", postId)
    Call SetFlash("success", "Comment added.")
    Call RedirectTo(APP_BASE_PATH & "?view=post&id=" & Url(postId))
End Sub

Sub HandleEditProfile()
    Dim displayName
    Dim bio
    Call RequireAuth()
    displayName = FormValue("display_name")
    bio = FormValue("bio")
    If Len(displayName) < 1 Or Len(displayName) > 40 Then
        Call SetFlash("error", "Display name must be between 1 and 40 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    If Len(bio) > 160 Then
        Call SetFlash("error", "Bio must not exceed 160 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    Call db.HSet(UserKey(currentUserId), "display_name", displayName)
    Call db.HSet(UserKey(currentUserId), "bio", bio)
    Call AddAjaxValue("display_name", displayName)
    Call SetFlash("success", "Profile updated.")
    Call RedirectTo(ProfilePath(currentUserId))
End Sub

Sub HandleBotSettings()
    Dim endpoint
    Dim model
    Dim apiKey
    Dim existingApiKey
    Dim botEnabled
    Call RequireAuth()
    endpoint = FormValue("bot_endpoint")
    model = FormValue("bot_model")
    apiKey = FormValue("bot_api_key")
    existingApiKey = UserField(currentUserId, "bot_api_key")
    botEnabled = False
    If FormValue("bot_enabled") = "1" Then botEnabled = True

    If Len(endpoint) > MAX_BOT_ENDPOINT_LENGTH Or (endpoint <> "" And Not ValidPostLink(endpoint)) Then
        Call SetFlash("error", "Enter a valid http:// or https:// API endpoint.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    If Len(model) > MAX_BOT_MODEL_LENGTH Then
        Call SetFlash("error", "Model names must not exceed 120 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    If Len(apiKey) > MAX_BOT_API_KEY_LENGTH Then
        Call SetFlash("error", "API keys must not exceed 512 characters.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    If apiKey = "" Then apiKey = existingApiKey
    If botEnabled And (endpoint = "" Or model = "" Or apiKey = "") Then
        Call SetFlash("error", "Endpoint, model, and API key are required for automatic bot management.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If

    Call db.HSet(UserKey(currentUserId), "bot_endpoint", endpoint)
    Call db.HSet(UserKey(currentUserId), "bot_model", model)
    If apiKey <> "" Then Call db.HSet(UserKey(currentUserId), "bot_api_key", apiKey)
    If botEnabled Then
        Call db.HSet(UserKey(currentUserId), "bot_enabled", "1")
    Else
        Call db.HSet(UserKey(currentUserId), "bot_enabled", "0")
    End If
    Call db.HSet(UserKey(currentUserId), "bot_updated_at", Timestamp())
    Call SetFlash("success", "Bot settings updated.")
    Call RedirectTo(APP_BASE_PATH & "?view=settings")
End Sub

Sub HandleSelectAvatar()
    Dim avatar
    Call RequireAuth()
    avatar = FormValue("avatar")
    If Not IsDefaultAvatar(avatar) Then
        Call SetFlash("error", "Choose one of the available default avatars.")
        Call RedirectTo(APP_BASE_PATH & "?view=settings")
    End If
    Call db.HSet(UserKey(currentUserId), "avatar", avatar)
    Call AddAjaxValue("avatar", avatar)
    Call SetFlash("success", "Avatar updated.")
    Call RedirectTo(APP_BASE_PATH & "?view=settings")
End Sub

Function UserFieldFromPost(postId, field)
    UserFieldFromPost = ValueOrEmpty(db.HGet(PostKey(postId), field))
End Function

Sub HandleAction(action)
    If action = "" Then Exit Sub
    If Not IsPost() Then
        Response.Status = "405 Method Not Allowed"
        If IsAjaxRequest() Then
            ajaxStatus = "405 Method Not Allowed"
            Call WriteAjaxResponse(False, "This action requires POST.", APP_BASE_PATH)
        End If
        Response.Write "This action requires POST."
        Response.End
    End If
    Call RequireCsrf()
    Select Case action
        Case "register"
            Call HandleRegister()
        Case "login"
            Call HandleLogin()
        Case "logout"
            Call HandleLogout()
        Case "publish"
            Call HandlePublish()
        Case "delete_post"
            Call HandleDeletePost()
        Case "follow"
            Call HandleFollow(True)
        Case "unfollow"
            Call HandleFollow(False)
        Case "like"
            Call HandleLike(True)
        Case "unlike"
            Call HandleLike(False)
        Case "comment"
            Call HandleComment()
        Case "edit_profile"
            Call HandleEditProfile()
        Case "save_bot_settings"
            Call HandleBotSettings()
        Case "select_avatar"
            Call HandleSelectAvatar()
        Case Else
            Response.Status = "400 Bad Request"
            If IsAjaxRequest() Then
                ajaxStatus = "400 Bad Request"
                Call WriteAjaxResponse(False, "Unknown action.", APP_BASE_PATH)
            End If
            Response.Write "Unknown action."
            Response.End
    End Select
End Sub

Sub RenderAvatar(userId, sizeName)
    Response.Write "<img class=""avatar avatar-" & sizeName & """ src=""" & Html(ImageUrl(AvatarPath(userId))) & """ alt="""">"
End Sub

Sub RenderUserLink(userId)
    Response.Write "<a class=""user-name"" href=""" & ProfilePath(userId) & """>" & Html(UserDisplayName(userId)) & "</a>"
    Response.Write "<a class=""user-handle"" href=""" & ProfilePath(userId) & """>@"
    Response.Write Html(UserField(userId, "username")) & "</a>"
End Sub

Sub RenderFollowButton(targetId)
    If currentUserId = "" Or currentUserId = targetId Then Exit Sub
    If IsFollowing(currentUserId, targetId) Then
        Response.Write "<form method=""post"" class=""inline-form""><input type=""hidden"" name=""action"" value=""unfollow"">"
        Response.Write "<input type=""hidden"" name=""target_id"" value=""" & Html(targetId) & """>"
        Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
        Response.Write "<button class=""button button-secondary button-small"" type=""submit"">Following</button></form>"
    Else
        Response.Write "<form method=""post"" class=""inline-form""><input type=""hidden"" name=""action"" value=""follow"">"
        Response.Write "<input type=""hidden"" name=""target_id"" value=""" & Html(targetId) & """>"
        Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
        Response.Write "<button class=""button button-primary button-small"" type=""submit"">Follow</button></form>"
    End If
End Sub

Function UiIcon(name)
    Dim paths
    paths = ""
    Select Case name
        Case "smile"
            paths = "<circle cx=""12"" cy=""12"" r=""10""></circle><path d=""M8 14s1.5 2 4 2 4-2 4-2""></path><line x1=""9"" x2=""9.01"" y1=""9"" y2=""9""></line><line x1=""15"" x2=""15.01"" y1=""9"" y2=""9""></line>"
        Case "image"
            paths = "<rect width=""18"" height=""18"" x=""3"" y=""3"" rx=""2"" ry=""2""></rect><circle cx=""9"" cy=""9"" r=""2""></circle><path d=""m21 15-5-5L5 21""></path>"
        Case "link"
            paths = "<path d=""M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71""></path><path d=""M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71""></path>"
        Case "heart"
            paths = "<path d=""M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z""></path>"
        Case "message"
            paths = "<path d=""M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4Z""></path>"
        Case "eye"
            paths = "<path d=""M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0Z""></path><circle cx=""12"" cy=""12"" r=""3""></circle>"
        Case "eye-off"
            paths = "<path d=""M10.73 5.08a10.74 10.74 0 0 1 11.21 6.57 1 1 0 0 1 0 .7 10.8 10.8 0 0 1-1.44 2.49""></path><path d=""M14.08 14.16a3 3 0 0 1-4.24-4.24""></path><path d=""M17.48 17.5a10.75 10.75 0 0 1-15.42-5.15 1 1 0 0 1 0-.7 10.75 10.75 0 0 1 4.45-5.14""></path><path d=""m2 2 20 20""></path>"
        Case "arrow-left"
            paths = "<path d=""m12 19-7-7 7-7""></path><path d=""M19 12H5""></path>"
    End Select
    UiIcon = "<svg class=""ui-icon ui-icon-" & Html(name) & """ viewBox=""0 0 24 24"" aria-hidden=""true"" focusable=""false"">" & paths & "</svg>"
End Function

Sub RenderPost(postId, showComments)
    Dim authorId
    Dim body
    Dim imagePath
    Dim linkUrl
    Dim linkLabel
    Dim createdAt
    Dim likeCount
    Dim commentCount
    Dim liked
    Dim commentLabel
    Dim likeLabel
    authorId = UserFieldFromPost(postId, "author_id")
    If authorId = "" Then Exit Sub
    body = UserFieldFromPost(postId, "body")
    imagePath = UserFieldFromPost(postId, "image")
    linkUrl = UserFieldFromPost(postId, "link_url")
    linkLabel = UserFieldFromPost(postId, "link_label")
    createdAt = UserFieldFromPost(postId, "created_at")
    likeCount = SetCount(RedisKey("post:" & postId & ":likes"))
    commentCount = ListCount(RedisKey("post:" & postId & ":comments"))
    liked = IsLiked(postId, currentUserId)
    commentLabel = "View " & commentCount & " comments"
    If commentCount = 1 Then commentLabel = "View 1 comment"
    Response.Write "<article class=""post-card"" data-post-id=""" & Html(postId) & """><div class=""post-head"">"
    Call RenderAvatar(authorId, "medium")
    Response.Write "<div class=""post-author"">"
    Call RenderUserLink(authorId)
    Response.Write "<time>" & Html(createdAt) & "</time></div>"
    If authorId = currentUserId Then
        Response.Write "<form method=""post"" class=""inline-form post-menu""><input type=""hidden"" name=""action"" value=""delete_post"">"
        Response.Write "<input type=""hidden"" name=""post_id"" value=""" & Html(postId) & """><input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
        Response.Write "<button class=""icon-button"" type=""submit"" title=""Delete post"" aria-label=""Delete post"">&times;</button></form>"
    End If
    Response.Write "</div><div class=""post-content"">"
    If body <> "" Then Response.Write "<div class=""post-body"">" & TextWithTopics(body) & "</div>"
    If imagePath <> "" Then Response.Write "<img class=""post-image"" src=""" & Html(ImageUrl(imagePath)) & """ alt=""Post image"" loading=""lazy"">"
    If linkUrl <> "" And ValidPostLink(linkUrl) Then
        If linkLabel = "" Then linkLabel = linkUrl
        Response.Write "<a class=""post-link"" href=""" & Html(linkUrl) & """ target=""_blank"" rel=""noopener noreferrer"">" & UiIcon("link") & "<span>" & Html(linkLabel) & "</span></a>"
    End If
    Response.Write "</div><div class=""post-actions"">"
    Response.Write "<a class=""post-action post-comment-action"" href=""" & APP_BASE_PATH & "?view=post&id=" & Url(postId) & """ title=""" & commentLabel & """ aria-label=""" & commentLabel & """>" & UiIcon("message") & "<strong aria-hidden=""true"">" & commentCount & "</strong></a>"
    If currentUserId <> "" Then
        likeLabel = "Like post, " & likeCount & " likes"
        If likeCount = 1 Then likeLabel = "Like post, 1 like"
        If liked Then
            likeLabel = "Unlike post, " & likeCount & " likes"
            If likeCount = 1 Then likeLabel = "Unlike post, 1 like"
        End If
        Response.Write "<form method=""post"" class=""inline-form""><input type=""hidden"" name=""action"" value="""
        If liked Then
            Response.Write "unlike"
        Else
            Response.Write "like"
        End If
        Response.Write """><input type=""hidden"" name=""post_id"" value=""" & Html(postId) & """><input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
        Response.Write "<button class=""post-action post-like-action"
        If liked Then Response.Write " active"
        Response.Write """ type=""submit"" title=""" & likeLabel & """ aria-label=""" & likeLabel & """>" & UiIcon("heart")
        Response.Write "<strong aria-hidden=""true"">" & likeCount & "</strong></button></form>"
    Else
        likeLabel = likeCount & " likes"
        If likeCount = 1 Then likeLabel = "1 like"
        Response.Write "<span class=""post-action post-like-action is-disabled"" title=""" & likeLabel & """ aria-label=""" & likeLabel & """>" & UiIcon("heart") & "<strong aria-hidden=""true"">" & likeCount & "</strong></span>"
    End If
    Response.Write "</div>"
    If showComments Then Call RenderComments(postId)
    Response.Write "</article>"
End Sub

Sub RenderComments(postId)
    Dim comments
    Dim commentId
    Dim authorId
    comments = db.LRange(RedisKey("post:" & postId & ":comments"), 0, -1)
    Response.Write "<section class=""comments""><h2>Conversation</h2>"
    If IsArray(comments) Then
        For Each commentId In comments
            authorId = ValueOrEmpty(db.HGet(CommentKey(commentId), "author_id"))
            If authorId <> "" Then
                Response.Write "<div class=""comment"">"
                Call RenderAvatar(authorId, "small")
                Response.Write "<div><div class=""comment-meta"">"
                Call RenderUserLink(authorId)
                Response.Write " <time>" & Html(db.HGet(CommentKey(commentId), "created_at")) & "</time></div>"
                Response.Write "<p>" & TextWithTopics(db.HGet(CommentKey(commentId), "body")) & "</p></div></div>"
            End If
        Next
    End If
    If currentUserId <> "" Then
        Response.Write "<form method=""post"" class=""comment-form""><input type=""hidden"" name=""action"" value=""comment"">"
        Response.Write "<input type=""hidden"" name=""post_id"" value=""" & Html(postId) & """><input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
        Response.Write "<input name=""body"" maxlength=""" & MAX_COMMENT_LENGTH & """ placeholder=""Write a comment"" required>"
        Response.Write "<button class=""button button-primary button-small"" type=""submit"">Reply</button></form>"
    End If
    Response.Write "</section>"
End Sub

Sub RenderComposer()
    If currentUserId = "" Then Exit Sub
    Response.Write "<section class=""composer panel""><form action=""publish-post.asp"" method=""post"" enctype=""multipart/form-data"" id=""post-composer"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label for=""post-body"">What is happening?</label>"
    Response.Write "<textarea id=""post-body"" name=""body"" maxlength=""" & MAX_POST_LENGTH & """ placeholder=""Share an update...""></textarea>"
    Response.Write "<div class=""composer-tools"" aria-label=""Add to post"">"
    Response.Write "<button class=""composer-tool"" type=""button"" data-composer-toggle=""emoji"" title=""Add emoji"" aria-label=""Add emoji"" aria-expanded=""false"">" & UiIcon("smile") & "</button>"
    Response.Write "<label class=""composer-tool"" title=""Add image"" aria-label=""Add image"">" & UiIcon("image") & "<input id=""post-image-input"" type=""file"" name=""image"" accept=""image/jpeg,image/png,image/webp""></label>"
    Response.Write "<button class=""composer-tool"" type=""button"" data-composer-toggle=""link"" title=""Add link"" aria-label=""Add link"" aria-expanded=""false"">" & UiIcon("link") & "</button>"
    Response.Write "<div class=""emoji-picker"" data-composer-panel=""emoji"" hidden>"
    Response.Write "<button type=""button"">&#128512;</button><button type=""button"">&#128514;</button><button type=""button"">&#128525;</button><button type=""button"">&#129321;</button><button type=""button"">&#129300;</button><button type=""button"">&#128077;</button><button type=""button"">&#128079;</button><button type=""button"">&#128293;</button><button type=""button"">&#10084;&#65039;</button><button type=""button"">&#127881;</button><button type=""button"">&#128640;</button><button type=""button"">&#10024;</button>"
    Response.Write "</div><div class=""link-editor"" data-composer-panel=""link"" hidden>"
    Response.Write "<label>URL<input type=""url"" name=""link_url"" maxlength=""" & MAX_POST_LINK_LENGTH & """ placeholder=""Enter a URL""></label>"
    Response.Write "<label>Label <span>(optional)</span><input name=""link_label"" maxlength=""" & MAX_POST_LINK_LABEL_LENGTH & """ placeholder=""Link title""></label></div></div>"
    Response.Write "<div class=""image-preview"" id=""post-image-preview"" hidden><img alt=""Selected image preview""><div><strong></strong><span></span></div><button type=""button"" title=""Remove image"" aria-label=""Remove image"">&times;</button></div>"
    Response.Write "<div class=""composer-error"" id=""composer-error"" role=""alert"" hidden></div>"
    Response.Write "<div class=""composer-footer""><span><strong id=""post-character-count"">0</strong> / " & MAX_POST_LENGTH & "</span>"
    Response.Write "<button class=""button button-primary"" type=""submit"">Post</button></div></form></section>"
End Sub

Function FeedPageNumber()
    Dim value
    value = QueryValue("page")
    FeedPageNumber = 1
    If value = "" Or Not IsNumeric(value) Or Len(value) > 6 Then Exit Function
    If CDbl(value) < 1 Or CDbl(value) > 1000 Then Exit Function
    FeedPageNumber = CLng(value)
End Function

Function FeedListKey(feedKind, userId)
    If feedKind = "profile" Then
        FeedListKey = RedisKey("user:" & userId & ":posts")
    ElseIf feedKind = "topic" Then
        FeedListKey = RedisKey("topic:" & LCase(userId) & ":posts")
    Else
        FeedListKey = RedisKey("posts:global")
    End If
End Function

Function FeedPostVisible(feedKind, authorId)
    FeedPostVisible = feedKind <> "home" Or currentUserId = "" Or authorId = currentUserId Or IsFollowing(currentUserId, authorId)
End Function

Function FeedPagePath(feedKind, userId, pageNumber)
    Dim path
    If feedKind = "discover" Then
        path = APP_BASE_PATH & "?view=discover"
    ElseIf feedKind = "profile" Then
        path = APP_BASE_PATH & "?view=profile&id=" & Url(userId)
    ElseIf feedKind = "topic" Then
        path = APP_BASE_PATH & "?view=topic&name=" & Url(userId)
    Else
        path = APP_BASE_PATH & "?"
    End If
    If Right(path, 1) <> "?" Then path = path & "&"
    FeedPagePath = path & "page=" & pageNumber
End Function

Sub RenderFeedPagination(feedKind, userId, pageNumber, hasMore)
    If pageNumber <= 1 And Not hasMore Then Exit Sub
    If hasMore Then
        Response.Write "<div class=""feed-pagination"" aria-hidden=""true"">"
        Response.Write "<div class=""feed-page-sentinel"" data-feed-kind=""" & Html(feedKind) & """ data-feed-id=""" & Html(userId) & """ data-page=""" & CStr(pageNumber + 1) & """></div>"
        Response.Write "</div>"
    End If
    Response.Write "<noscript><nav class=""feed-page-fallback"" aria-label=""Feed pagination"">"
    If pageNumber > 1 Then
        Response.Write "<a class=""button button-secondary"" href=""" & FeedPagePath(feedKind, userId, pageNumber - 1) & """>Previous</a>"
    End If
    If hasMore Then
        Response.Write "<a class=""button button-secondary"" href=""" & FeedPagePath(feedKind, userId, pageNumber + 1) & """>Next page</a>"
    End If
    Response.Write "</nav></noscript>"
End Sub

Sub RenderFeedPage(feedKind, userId, pageNumber, wrapContainer)
    Dim ids
    Dim postId
    Dim authorId
    Dim listKey
    Dim batchSize
    Dim batchCount
    Dim sourceOffset
    Dim matchIndex
    Dim pageStart
    Dim shown
    Dim hasMore
    Dim finished
    Dim directOffset
    listKey = FeedListKey(feedKind, userId)
    batchSize = FEED_PAGE_SIZE * 4
    pageStart = (pageNumber - 1) * FEED_PAGE_SIZE
    directOffset = feedKind <> "home" Or currentUserId = ""
    If directOffset Then
        sourceOffset = pageStart
        matchIndex = pageStart
    Else
        sourceOffset = 0
        matchIndex = 0
    End If
    shown = 0
    hasMore = False
    finished = False
    If wrapContainer Then Response.Write "<div id=""feed-list"" class=""feed-list"" data-page=""" & pageNumber & """>"
    Do While Not finished
        ids = db.LRange(listKey, sourceOffset, sourceOffset + batchSize - 1)
        If Not IsArray(ids) Then Exit Do
        batchCount = UBound(ids) - LBound(ids) + 1
        For Each postId In ids
            authorId = UserFieldFromPost(postId, "author_id")
            If authorId <> "" And FeedPostVisible(feedKind, authorId) Then
                If matchIndex >= pageStart Then
                    If shown < FEED_PAGE_SIZE Then
                        Call RenderPost(CStr(postId), False)
                        shown = shown + 1
                    Else
                        hasMore = True
                        finished = True
                        Exit For
                    End If
                End If
                matchIndex = matchIndex + 1
            End If
        Next
        sourceOffset = sourceOffset + batchCount
        If batchCount < batchSize Then finished = True
    Loop
    If shown = 0 Then
        If pageNumber > 1 Then
            Response.Write "<div class=""empty-state""><strong>No posts on this page</strong><span>Use the previous page to continue browsing.</span></div>"
        Else
            Response.Write "<div class=""empty-state""><strong>No posts yet</strong><span>Follow people or publish the first update.</span></div>"
        End If
    End If
    If wrapContainer Then Response.Write "</div>"
    Call RenderFeedPagination(feedKind, userId, pageNumber, hasMore)
End Sub

Sub RenderFeed(feedKind, userId)
    Call RenderFeedPage(feedKind, userId, FeedPageNumber(), True)
End Sub

Sub RenderTopics()
    Dim topics
    Dim index
    Dim topic
    Dim displayName
    Dim count
    Dim shown
    topics = db.Execute("ZREVRANGE", RedisKey("topics:counts"), "0", "49", "WITHSCORES")
    shown = 0
    Response.Write "<section class=""panel topics-panel""><div class=""section-heading""><h1>Topics</h1><span>Popular conversations</span></div><div class=""topic-list"">"
    If IsArray(topics) Then
        For index = LBound(topics) To UBound(topics) Step 2
            topic = CStr(topics(index))
            displayName = ValueOrEmpty(db.HGet(RedisKey("topic:names"), topic))
            If displayName = "" Then displayName = topic
            count = CLng(CDbl(topics(index + 1)))
            Response.Write "<a class=""topic-row"" href=""" & TopicPath(topic) & """><span class=""topic-symbol"">#</span><span><strong>" & Html(displayName) & "</strong><small>" & count & " "
            If count = 1 Then
                Response.Write "post"
            Else
                Response.Write "posts"
            End If
            Response.Write "</small></span></a>"
            shown = shown + 1
        Next
    End If
    If shown = 0 Then
        Response.Write "<div class=""empty-state""><strong>No topics yet</strong><span>Publish a post containing #topic# to start one.</span></div>"
    End If
    Response.Write "</div></section>"
End Sub

Sub RenderTopic(topic)
    Dim normalized
    Dim displayName
    normalized = LCase(Trim(topic))
    displayName = ValueOrEmpty(db.HGet(RedisKey("topic:names"), normalized))
    If displayName = "" Then displayName = Trim(topic)
    Response.Write "<div class=""page-heading topic-heading""><h1>#" & Html(displayName) & "#</h1><a href=""" & CurrentPath("topics") & """>All topics</a></div>"
    Call RenderFeed("topic", normalized)
End Sub

Sub RenderUserRow(userId)
    Response.Write "<div class=""user-row"">"
    Call RenderAvatar(userId, "medium")
    Response.Write "<div class=""user-row-main"">"
    Call RenderUserLink(userId)
    Response.Write "<p>" & Html(UserField(userId, "bio")) & "</p></div>"
    Call RenderFollowButton(userId)
    Response.Write "</div>"
End Sub

Sub RenderPeopleList(kind, userId)
    Dim ids
    Dim memberId
    If kind = "followers" Then
        ids = db.SMembers(RedisKey("followers:" & userId))
    Else
        ids = db.SMembers(RedisKey("following:" & userId))
    End If
    Response.Write "<section class=""panel people-panel""><div class=""section-heading""><h1>" & Html(UserDisplayName(userId)) & "</h1>"
    Response.Write "<span>" & Html(kind) & "</span></div>"
    If IsArray(ids) Then
        For Each memberId In ids
            Call RenderUserRow(CStr(memberId))
        Next
    End If
    Response.Write "</section>"
End Sub

Sub RenderSearch(query)
    Dim users
    Dim userId
    Dim needle
    Dim found
    needle = LCase(Trim(query))
    found = 0
    Response.Write "<section class=""panel people-panel""><div class=""section-heading""><h1>People</h1><span>Search results</span></div>"
    users = db.SMembers(RedisKey("users"))
    If IsArray(users) Then
        For Each userId In users
            If needle = "" Or InStr(1, LCase(UserField(userId, "username")), needle, 0) > 0 Or InStr(1, LCase(UserDisplayName(userId)), needle, 0) > 0 Then
                Call RenderUserRow(CStr(userId))
                found = found + 1
            End If
        Next
    End If
    If found = 0 Then Response.Write "<div class=""empty-state""><strong>No people found</strong><span>Try another name or username.</span></div>"
    Response.Write "</section>"
End Sub

Sub RenderProfileHeader(userId)
    Response.Write "<section class=""profile-card panel""><div class=""profile-cover""></div><div class=""profile-main"">"
    Call RenderAvatar(userId, "large")
    Response.Write "<div class=""profile-copy""><h1>" & Html(UserDisplayName(userId)) & "</h1><span>@" & Html(UserField(userId, "username")) & "</span>"
    Response.Write "<p>" & Html(UserField(userId, "bio")) & "</p></div><div class=""profile-action"">"
    If currentUserId = userId Then
        Response.Write "<a class=""button button-secondary"" href=""" & APP_BASE_PATH & "?view=settings"">Edit profile</a>"
    Else
        Call RenderFollowButton(userId)
    End If
    Response.Write "</div></div><div class=""profile-stats"">"
    Response.Write "<a href=""" & APP_BASE_PATH & "?view=following&id=" & Url(userId) & """><strong>" & SetCount(RedisKey("following:" & userId)) & "</strong><span>Following</span></a>"
    Response.Write "<a href=""" & APP_BASE_PATH & "?view=followers&id=" & Url(userId) & """><strong>" & SetCount(RedisKey("followers:" & userId)) & "</strong><span>Followers</span></a>"
    Response.Write "<span><strong>" & ListCount(RedisKey("user:" & userId & ":posts")) & "</strong><span>Posts</span></span>"
    Response.Write "</div></section>"
End Sub

Sub RenderAccountPanel()
    Response.Write "<section class=""auth-shell""><a class=""auth-home-link"" href=""" & APP_BASE_PATH & """>" & UiIcon("arrow-left") & "<span>Back to home</span></a>"
    Response.Write "<div class=""auth-grid""><div class=""auth-intro""><span class=""brand-mark large-mark"">Y</span>"
    Response.Write "<h1>Join the conversation.</h1><p>Follow people you care about, share updates, and discover what is happening.</p>"
    Response.Write "<p class=""vision-statement"">Connect everything. Hear the world's voice.</p></div>"
    Response.Write "<div class=""auth-forms panel""><div class=""auth-block""><h2>Sign in</h2><form method=""post"">"
    Response.Write "<input type=""hidden"" name=""action"" value=""login""><input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label><span class=""field-label"">Username<span class=""required-marker"" aria-hidden=""true"">*</span></span><input name=""username"" autocomplete=""username"" required></label>"
    Response.Write "<label><span class=""field-label"">Password<span class=""required-marker"" aria-hidden=""true"">*</span></span><input type=""password"" name=""password"" autocomplete=""current-password"" required></label>"
    Response.Write "<button class=""button button-primary button-wide"" type=""submit"">Sign in</button></form></div>"
    Response.Write "<div class=""auth-divider""><span>New to uYasoo?</span></div><div class=""auth-block""><h2>Create an account</h2><form method=""post"">"
    Response.Write "<input type=""hidden"" name=""action"" value=""register""><input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label><span class=""field-label"">Display name<span class=""required-marker"" aria-hidden=""true"">*</span></span><input name=""display_name"" maxlength=""40"" autocomplete=""name"" required></label>"
    Response.Write "<label><span class=""field-label"">Username<span class=""required-marker"" aria-hidden=""true"">*</span></span><input name=""username"" minlength=""3"" maxlength=""20"" pattern=""[A-Za-z0-9_]+"" autocomplete=""username"" required></label>"
    Response.Write "<label><span class=""field-label"">Email<span class=""required-marker"" aria-hidden=""true"">*</span></span><input type=""email"" name=""email"" maxlength=""" & MAX_EMAIL_LENGTH & """ autocomplete=""email"" required></label>"
    Response.Write "<label><span class=""field-label"">Password<span class=""required-marker"" aria-hidden=""true"">*</span></span><input type=""password"" name=""password"" minlength=""8"" maxlength=""128"" autocomplete=""new-password"" required></label>"
    Response.Write "<label><span class=""field-label"">Verification code<span class=""required-marker"" aria-hidden=""true"">*</span></span><span class=""captcha-row""><input name=""captcha"" maxlength=""6"" autocomplete=""off"" spellcheck=""false"" required>"
    Response.Write "<img id=""register-captcha"" src=""captcha.asp"" alt=""Verification code""><button id=""refresh-captcha"" class=""captcha-refresh"" type=""button"" title=""New verification code"" aria-label=""New verification code"">&#8635;</button></span></label>"
    Response.Write "<button class=""button button-secondary button-wide"" type=""submit"">Create account</button></form></div></div></div></section>"
End Sub

Sub RenderSettings()
    Dim index
    Dim avatar
    Dim botEndpoint
    Dim botModel
    Dim botEnabled
    Dim hasBotApiKey
    avatar = AvatarPath(currentUserId)
    botEndpoint = UserField(currentUserId, "bot_endpoint")
    botModel = UserField(currentUserId, "bot_model")
    botEnabled = UserField(currentUserId, "bot_enabled") = "1"
    hasBotApiKey = UserField(currentUserId, "bot_api_key") <> ""
    Response.Write "<section class=""panel settings-panel avatar-settings""><div class=""section-heading""><h1>Profile picture</h1><span>JPG, PNG, or WebP up to 1 MB</span></div>"
    Response.Write "<div class=""avatar-upload-row"">"
    Call RenderAvatar(currentUserId, "large")
    Response.Write "<form action=""upload-avatar.asp"" method=""post"" enctype=""multipart/form-data"" class=""avatar-upload-form"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label class=""file-picker"">Choose image<input type=""file"" name=""avatar"" accept=""image/jpeg,image/png,image/webp"" required></label>"
    Response.Write "<button class=""button button-primary"" type=""submit"">Upload avatar</button></form></div>"
    Response.Write "<form method=""post"" class=""default-avatar-form""><input type=""hidden"" name=""action"" value=""select_avatar"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """><fieldset><legend>Or choose a default</legend><div class=""avatar-options"">"
    For index = 1 To DEFAULT_AVATAR_COUNT
        Response.Write "<label><input type=""radio"" name=""avatar"" value=""" & DefaultAvatarPath(index) & """"
        If avatar = DefaultAvatarPath(index) Then Response.Write " checked"
        Response.Write "><img src=""" & DefaultAvatarPath(index) & """ alt=""Default avatar " & index & """></label>"
    Next
    Response.Write "</div></fieldset><button class=""button button-secondary"" type=""submit"">Use selected avatar</button></form></section>"
    Response.Write "<section class=""panel settings-panel profile-settings""><div class=""section-heading""><h1>Edit profile</h1><span>Public information</span></div>"
    Response.Write "<form method=""post"" class=""settings-form""><input type=""hidden"" name=""action"" value=""edit_profile"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label>Display name<input name=""display_name"" maxlength=""40"" value=""" & Html(UserDisplayName(currentUserId)) & """ required></label>"
    Response.Write "<label>Bio<textarea name=""bio"" maxlength=""160"" placeholder=""Tell people about yourself"">" & Html(UserField(currentUserId, "bio")) & "</textarea></label>"
    Response.Write "<button class=""button button-primary"" type=""submit"">Save changes</button></form></section>"
    Response.Write "<section class=""panel settings-panel bot-settings""><div class=""section-heading""><h1>AI Bot</h1><span>Large language model</span></div>"
    Response.Write "<form method=""post"" class=""settings-form"" id=""bot-settings-form""><input type=""hidden"" name=""action"" value=""save_bot_settings"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """>"
    Response.Write "<label>API endpoint<span class=""masked-input""><input id=""bot-endpoint"" type=""password"" name=""bot_endpoint"" maxlength=""" & MAX_BOT_ENDPOINT_LENGTH & """ value=""" & Html(botEndpoint) & """ placeholder=""Enter an API endpoint""><button class=""visibility-toggle"" type=""button"" data-visibility-target=""bot-endpoint"" data-visibility-label=""API endpoint"" title=""Show API endpoint"" aria-label=""Show API endpoint"" aria-pressed=""false"">" & UiIcon("eye") & UiIcon("eye-off") & "</button></span></label>"
    Response.Write "<label>Model<span class=""masked-input""><input id=""bot-model"" type=""password"" name=""bot_model"" maxlength=""" & MAX_BOT_MODEL_LENGTH & """ value=""" & Html(botModel) & """ placeholder=""Model name""><button class=""visibility-toggle"" type=""button"" data-visibility-target=""bot-model"" data-visibility-label=""model"" title=""Show model"" aria-label=""Show model"" aria-pressed=""false"">" & UiIcon("eye") & UiIcon("eye-off") & "</button></span></label>"
    Response.Write "<label>API key<span class=""masked-input""><input id=""bot-api-key"" type=""password"" name=""bot_api_key"" maxlength=""" & MAX_BOT_API_KEY_LENGTH & """ value=""" & Html(UserField(currentUserId, "bot_api_key")) & """ autocomplete=""off"" data-has-key="""
    If hasBotApiKey Then
        Response.Write "1"
    Else
        Response.Write "0"
    End If
    Response.Write """><button class=""visibility-toggle"" type=""button"" data-visibility-target=""bot-api-key"" data-visibility-label=""API key"" title=""Show API key"" aria-label=""Show API key"" aria-pressed=""false"">" & UiIcon("eye") & UiIcon("eye-off") & "</button></span></label>"
    Response.Write "<label class=""checkbox-row""><input id=""bot-enabled"" type=""checkbox"" name=""bot_enabled"" value=""1"""
    If botEnabled Then Response.Write " checked"
    Response.Write "><span>Enable automatic bot management</span></label>"
    Response.Write "<button class=""button button-primary"" type=""submit"">Save bot settings</button></form></section>"
    Response.Write "<section class=""panel settings-panel session-settings""><div class=""section-heading""><h1>Session</h1><span>@" & Html(UserField(currentUserId, "username")) & "</span></div>"
    Response.Write "<form method=""post"" class=""session-form""><input type=""hidden"" name=""action"" value=""logout"">"
    Response.Write "<input type=""hidden"" name=""csrf"" value=""" & Html(CsrfToken()) & """><button class=""button button-secondary"" type=""submit"">Sign out</button></form></section>"
End Sub

Sub RenderLeftNavigation(activeView)
    Response.Write "<aside class=""left-rail""><nav class=""side-nav"" aria-label=""Primary navigation"">"
    Response.Write "<a"
    If activeView = "home" Then Response.Write " class=""active"""
    Response.Write " href=""" & APP_BASE_PATH & """>Home</a>"
    Response.Write "<a"
    If activeView = "discover" Then Response.Write " class=""active"""
    Response.Write " href=""" & APP_BASE_PATH & "?view=discover"">Discover</a>"
    Response.Write "<a"
    If activeView = "topics" Or activeView = "topic" Then Response.Write " class=""active"""
    Response.Write " href=""" & APP_BASE_PATH & "?view=topics"">Topics</a>"
    If currentUserId <> "" Then
        Response.Write "<a"
        If activeView = "profile" Then Response.Write " class=""active"""
        Response.Write " href=""" & ProfilePath(currentUserId) & """>Profile</a>"
        Response.Write "<a"
        If activeView = "settings" Then Response.Write " class=""active"""
        Response.Write " href=""" & APP_BASE_PATH & "?view=settings"">Settings</a>"
    End If
    Response.Write "</nav></aside>"
End Sub

Sub RenderRightRail()
    Dim users
    Dim userId
    Dim shown
    Response.Write "<aside class=""right-rail""><section class=""panel search-panel""><form method=""get"">"
    Response.Write "<input type=""hidden"" name=""view"" value=""search""><label class=""search-box""><span class=""sr-only"">Search people</span>"
    Response.Write "<input name=""q"" value=""" & Html(QueryValue("q")) & """ placeholder=""Search people""></label></form></section>"
    If currentUserId <> "" Then
        Response.Write "<section class=""panel suggestions""><div class=""section-heading""><h2>Who to follow</h2></div>"
        users = db.SMembers(RedisKey("users"))
        shown = 0
        If IsArray(users) Then
            For Each userId In users
                If CStr(userId) <> currentUserId And Not IsFollowing(currentUserId, CStr(userId)) And shown < 4 Then
                    Call RenderUserRow(CStr(userId))
                    shown = shown + 1
                End If
            Next
        End If
        If shown = 0 Then Response.Write "<p class=""quiet"">You are caught up.</p>"
        Response.Write "</section>"
    End If
    Response.Write "<footer class=""site-footer"">You can connect everything. Hear the world's voice.</footer></aside>"
End Sub
%>
