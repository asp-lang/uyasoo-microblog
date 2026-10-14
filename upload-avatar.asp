<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<!--#include file="upload-utils.asp" -->
<%
Sub UploadFailure(message)
    Call SetFlash("error", message)
    Call RedirectTo(APP_BASE_PATH & "?view=settings")
End Sub

Response.ContentType = "text/html"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

currentUserId = ResolveCurrentUser()
If currentUserId = "" Then
    ajaxStatus = "401 Unauthorized"
    Call UploadFailure("Sign in to upload an avatar.")
End If

If UCase(Request.ServerVariables("REQUEST_METHOD")) <> "POST" Then
    Response.Status = "405 Method Not Allowed"
    Response.Write "This endpoint requires POST."
    Response.End
End If

Dim contentType
Dim totalBytes
Dim body
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
Dim csrf
Dim avatarData
Dim extension
Dim storedName
Dim storedPath
Dim stream

contentType = LCase(ValueOrEmpty(Request.ServerVariables("CONTENT_TYPE")))
If InStr(1, contentType, "multipart/form-data", 0) <> 1 Then Call UploadFailure("The avatar form must use multipart upload.")

totalBytes = CLng(Request.TotalBytes)
If totalBytes < 1 Or totalBytes > MAX_AVATAR_BYTES + 65536 Then Call UploadFailure("The uploaded image must not exceed 1 MB.")

body = Request.BinaryRead(totalBytes)
crlf = ChrB(13) & ChrB(10)
headerSeparator = crlf & crlf
boundaryEnd = InStrB(1, body, crlf)
If boundaryEnd <= 1 Then Call UploadFailure("The multipart upload is malformed.")
boundary = MidB(body, 1, boundaryEnd - 1)
position = 1
csrf = ""
originalFilename = ""

Do
    position = InStrB(position, body, boundary)
    If position = 0 Then Exit Do
    headerStart = position + LenB(boundary) + LenB(crlf)
    If AscB(MidB(body, position + LenB(boundary), 1)) = 45 Then Exit Do
    dataStart = InStrB(headerStart, body, headerSeparator)
    If dataStart = 0 Then Call UploadFailure("The multipart headers are malformed.")
    headers = BinaryToText(MidB(body, headerStart, dataStart - headerStart))
    dataStart = dataStart + LenB(headerSeparator)
    nextBoundary = InStrB(dataStart, body, crlf & boundary)
    If nextBoundary = 0 Then Call UploadFailure("The multipart body is incomplete.")
    fieldName = HeaderParameter(headers, "name")
    If fieldName = "csrf" Then
        csrf = BinaryToText(MidB(body, dataStart, nextBoundary - dataStart))
    ElseIf fieldName = "avatar" Then
        originalFilename = HeaderParameter(headers, "filename")
        avatarData = MidB(body, dataStart, nextBoundary - dataStart)
    End If
    position = nextBoundary + LenB(crlf)
Loop

If IsEmpty(Session("csrf_token")) Or csrf = "" Or Not crypto.ConstantTimeEquals(CStr(Session("csrf_token")), csrf) Then
    Response.Status = "403 Forbidden"
    If IsAjaxRequest() Then
        ajaxStatus = "403 Forbidden"
        Call WriteAjaxResponse(False, "Invalid or expired form token.", APP_BASE_PATH & "?view=settings")
    End If
    Response.Write "Invalid or expired form token."
    Response.End
End If
If originalFilename = "" Or IsEmpty(avatarData) Or LenB(avatarData) < 12 Then Call UploadFailure("Choose a valid image file.")
If LenB(avatarData) > MAX_AVATAR_BYTES Then Call UploadFailure("The uploaded image must not exceed 1 MB.")

extension = ImageExtension(avatarData)
If extension = "" Then Call UploadFailure("Only valid JPG, PNG, and WebP images are accepted.")

storedName = "user-" & currentUserId & "-" & crypto.RandomHex(16) & "." & extension
storedPath = "assets/uploads/" & storedName
Set stream = Server.CreateObject("ADODB.Stream")
stream.Type = 1
stream.Open
stream.Write avatarData
stream.Position = 0
stream.SaveToFile Server.MapPath(storedPath), 2
stream.Close
Set stream = Nothing

Call CacheUploadedImage(storedPath, avatarData)
Call db.HSet(UserKey(currentUserId), "avatar", storedPath)
Call AddAjaxValue("avatar", ImageUrl(storedPath))
Call SetFlash("success", "Avatar uploaded.")
Call db.Close()
Call RedirectTo(APP_BASE_PATH & "?view=settings")
%>
