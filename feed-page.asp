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

Dim feedKind
Dim userId
Dim pageNumber
feedKind = LCase(QueryValue("kind"))
userId = QueryValue("id")
pageNumber = FeedPageNumber()

If feedKind <> "home" And feedKind <> "discover" And feedKind <> "profile" And feedKind <> "topic" Then
    Response.Status = "400 Bad Request"
    Response.Write "Invalid feed type."
ElseIf feedKind = "profile" And Not UserExists(userId) Then
    Response.Status = "404 Not Found"
    Response.Write "Account not found."
ElseIf feedKind = "topic" And (userId = "" Or Len(userId) > MAX_TOPIC_LENGTH) Then
    Response.Status = "400 Bad Request"
    Response.Write "Invalid topic."
Else
    Call RenderFeedPage(feedKind, userId, pageNumber, False)
End If

Call db.Close()
%>
