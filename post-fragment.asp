<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<%
Response.ContentType = "text/html"
Response.AddHeader "Cache-Control", "no-store"
Response.AddHeader "X-Content-Type-Options", "nosniff"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

currentUserId = ResolveCurrentUser()

Dim postId
Dim showComments
postId = QueryValue("id")
showComments = QueryValue("comments") = "1"

If Not IsNumeric(postId) Or Len(postId) > 10 Then
    Response.Status = "400 Bad Request"
    Response.Write "Invalid post identifier."
ElseIf CDbl(postId) < 1 Or CDbl(postId) > 2147483647 Then
    Response.Status = "400 Bad Request"
    Response.Write "Invalid post identifier."
ElseIf CLng(db.Exists(PostKey(postId))) <> 1 Then
    Response.Status = "404 Not Found"
    Response.Write "Post not found."
Else
    Call RenderPost(postId, showComments)
End If

Call db.Close()
%>
