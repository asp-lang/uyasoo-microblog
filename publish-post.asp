<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<!--#include file="upload-utils.asp" -->
<%
Sub PublishFailure(message)
    Call SetFlash("error", message)
    Call RedirectTo(APP_BASE_PATH)
End Sub

Response.ContentType = "text/html"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

currentUserId = ResolveCurrentUser()
If currentUserId = "" Then
    ajaxStatus = "401 Unauthorized"
    Call PublishFailure("Sign in to publish a post.")
End If

If UCase(Request.ServerVariables("REQUEST_METHOD")) <> "POST" Then
    Response.Status = "405 Method Not Allowed"
    Response.Write "This endpoint requires POST."
    Response.End
End If

Dim contentType
Dim totalBytes
Dim multipartBody
Dim boundary
Dim crlf
Dim headerSeparator
Dim boundaryEnd
Dim position
Dim headerStart
Dim dataStart
Dim nextBoundary
Dim headers
Dim fieldName
Dim originalFilename
Dim fieldData
Dim csrf
Dim body
Dim linkUrl
Dim linkLabel
Dim imageData
Dim extension
Dim storedName
Dim storedPath
Dim stream
Dim postId

contentType = LCase(ValueOrEmpty(Request.ServerVariables("CONTENT_TYPE")))
If InStr(1, contentType, "multipart/form-data", 0) <> 1 Then Call PublishFailure("The post form must use multipart upload.")

totalBytes = CLng(Request.TotalBytes)
If totalBytes < 1 Or totalBytes > MAX_POST_IMAGE_BYTES + 131072 Then Call PublishFailure("The post image must not exceed 5 MB.")

multipartBody = Request.BinaryRead(totalBytes)
crlf = ChrB(13) & ChrB(10)
headerSeparator = crlf & crlf
boundaryEnd = InStrB(1, multipartBody, crlf)
If boundaryEnd <= 1 Then Call PublishFailure("The multipart upload is malformed.")
boundary = MidB(multipartBody, 1, boundaryEnd - 1)
position = 1
csrf = ""
body = ""
linkUrl = ""
linkLabel = ""
originalFilename = ""

Do
    position = InStrB(position, multipartBody, boundary)
    If position = 0 Then Exit Do
    headerStart = position + LenB(boundary) + LenB(crlf)
    If AscB(MidB(multipartBody, position + LenB(boundary), 1)) = 45 Then Exit Do
    dataStart = InStrB(headerStart, multipartBody, headerSeparator)
    If dataStart = 0 Then Call PublishFailure("The multipart headers are malformed.")
    headers = BinaryToText(MidB(multipartBody, headerStart, dataStart - headerStart))
    dataStart = dataStart + LenB(headerSeparator)
    nextBoundary = InStrB(dataStart, multipartBody, crlf & boundary)
    If nextBoundary = 0 Then Call PublishFailure("The multipart body is incomplete.")
    fieldName = HeaderParameter(headers, "name")
    fieldData = MidB(multipartBody, dataStart, nextBoundary - dataStart)
    If fieldName = "csrf" Then
        csrf = BinaryUtf8ToText(fieldData)
    ElseIf fieldName = "body" Then
        body = Trim(BinaryUtf8ToText(fieldData))
    ElseIf fieldName = "link_url" Then
        linkUrl = Trim(BinaryUtf8ToText(fieldData))
    ElseIf fieldName = "link_label" Then
        linkLabel = Trim(BinaryUtf8ToText(fieldData))
    ElseIf fieldName = "image" Then
        originalFilename = HeaderParameter(headers, "filename")
        If originalFilename <> "" Then imageData = fieldData
    End If
    position = nextBoundary + LenB(crlf)
Loop

If IsEmpty(Session("csrf_token")) Or csrf = "" Or Not crypto.ConstantTimeEquals(CStr(Session("csrf_token")), csrf) Then
    Response.Status = "403 Forbidden"
    If IsAjaxRequest() Then
        ajaxStatus = "403 Forbidden"
        Call WriteAjaxResponse(False, "Invalid or expired form token.", APP_BASE_PATH)
    End If
    Response.Write "Invalid or expired form token."
    Response.End
End If

If Len(body) > MAX_POST_LENGTH Then Call PublishFailure("Posts must not exceed 280 characters.")
If Len(linkUrl) > MAX_POST_LINK_LENGTH Then Call PublishFailure("Links must not exceed 2048 characters.")
If Len(linkLabel) > MAX_POST_LINK_LABEL_LENGTH Then Call PublishFailure("Link labels must not exceed 120 characters.")
If linkUrl <> "" And Not ValidPostLink(linkUrl) Then Call PublishFailure("Links must use a valid http:// or https:// address.")
If linkUrl = "" And linkLabel <> "" Then Call PublishFailure("Add a URL for the link label.")
If body = "" And linkUrl = "" And IsEmpty(imageData) Then Call PublishFailure("Add text, an image, or a link before posting.")

storedPath = ""
If Not IsEmpty(imageData) Then
    If LenB(imageData) > MAX_POST_IMAGE_BYTES Then Call PublishFailure("The post image must not exceed 5 MB.")
    extension = ImageExtension(imageData)
    If extension = "" Then Call PublishFailure("Only valid JPG, PNG, and WebP images are accepted.")
    storedName = "post-" & currentUserId & "-" & crypto.RandomHex(16) & "." & extension
    storedPath = "assets/uploads/" & storedName
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.Write imageData
    stream.Position = 0
    stream.SaveToFile Server.MapPath(storedPath), 2
    stream.Close
    Set stream = Nothing
    Call CacheUploadedImage(storedPath, imageData)
End If

postId = StorePost(body, storedPath, linkUrl, linkLabel)
Call AddAjaxValue("post_id", postId)
Call SetFlash("success", "Your post is live.")
Call db.Close()
Call RedirectTo(APP_BASE_PATH)
%>
