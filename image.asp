<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<%
Response.AddHeader "X-Content-Type-Options", "nosniff"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

Dim requestMethod
Dim fileName
Dim imagePath
Dim imageData
Dim cacheValue
Dim cacheStatus
Dim contentType
Dim fileSystem
Dim stream

requestMethod = UCase(ValueOrEmpty(Request.ServerVariables("REQUEST_METHOD")))
If requestMethod <> "GET" And requestMethod <> "HEAD" Then
    Response.Status = "405 Method Not Allowed"
    Response.AddHeader "Allow", "GET, HEAD"
    Response.ContentType = "text/plain"
    Response.Write "This endpoint supports GET and HEAD."
    Call db.Close()
    Response.End
End If

fileName = QueryValue("name")
imagePath = "assets/uploads/" & fileName
If Not IsUploadedImagePath(imagePath) Then
    Response.Status = "404 Not Found"
    Response.ContentType = "text/plain"
    Response.Write "Image not found."
    Call db.Close()
    Response.End
End If

cacheValue = db.Get(UploadedImageCacheKey(imagePath))
cacheStatus = "HIT"
If IsNull(cacheValue) Or IsEmpty(cacheValue) Or LenB(cacheValue) = 0 Then
    Set fileSystem = Server.CreateObject("Scripting.FileSystemObject")
    If Not fileSystem.FileExists(Server.MapPath(imagePath)) Then
        Set fileSystem = Nothing
        Response.Status = "404 Not Found"
        Response.ContentType = "text/plain"
        Response.Write "Image not found."
        Call db.Close()
        Response.End
    End If
    Set fileSystem = Nothing

    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile Server.MapPath(imagePath)
    imageData = stream.Read
    stream.Close
    Set stream = Nothing
    Call CacheUploadedImage(imagePath, imageData)
    cacheStatus = "MISS"
Else
    imageData = cacheValue
End If

contentType = "image/jpeg"
If LCase(Right(fileName, 4)) = ".png" Then contentType = "image/png"
If LCase(Right(fileName, 5)) = ".webp" Then contentType = "image/webp"

Response.ContentType = contentType
Response.AddHeader "Cache-Control", "public, max-age=3600"
Response.AddHeader "Content-Length", CStr(LenB(imageData))
Response.AddHeader "X-Image-Cache", cacheStatus
If requestMethod = "GET" Then Response.BinaryWrite imageData

Call db.Close()
%>
