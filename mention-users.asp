<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<%
Function JsonString(value)
    Dim text
    text = ValueOrEmpty(value)
    text = Replace(text, "\", "\\")
    text = Replace(text, Chr(34), "\" & Chr(34))
    text = Replace(text, vbCrLf, "\n")
    text = Replace(text, vbCr, "\n")
    text = Replace(text, vbLf, "\n")
    JsonString = Chr(34) & text & Chr(34)
End Function

Response.ContentType = "application/json"
Response.AddHeader "Cache-Control", "no-store"
Response.AddHeader "X-Content-Type-Options", "nosniff"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

currentUserId = ResolveCurrentUser()
If currentUserId = "" Then
    Response.Status = "401 Unauthorized"
    Response.Write "{""users"":[]}"
    Call db.Close()
    Response.End
End If

Dim query
Dim users
Dim userId
Dim username
Dim displayName
Dim count

query = LCase(Left(QueryValue("q"), 20))
users = db.SMembers(RedisKey("users"))
count = 0
Response.Write "{""users"":["

If IsArray(users) Then
    For Each userId In users
        username = UserField(CStr(userId), "username")
        displayName = UserDisplayName(CStr(userId))
        If query = "" Or InStr(1, LCase(username), query, 0) > 0 Or InStr(1, LCase(displayName), query, 0) > 0 Then
            If count > 0 Then Response.Write ","
            Response.Write "{""id"":" & JsonString(CStr(userId))
            Response.Write ",""username"":" & JsonString(username)
            Response.Write ",""display_name"":" & JsonString(displayName)
            Response.Write ",""avatar"":" & JsonString(ImageUrl(AvatarPath(CStr(userId)))) & "}"
            count = count + 1
            If count = 8 Then Exit For
        End If
    Next
End If

Response.Write "]}"
Call db.Close()
%>
