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
If currentUserId = "" Then
    Response.Status = "401 Unauthorized"
    Call db.Close()
    Response.End
End If

Dim afterId
Dim afterValue
Dim latestId
Dim ids
Dim postId
Dim authorId

afterId = 0
afterValue = QueryValue("after")
If IsNumeric(afterValue) And Len(afterValue) <= 10 Then
    If CDbl(afterValue) >= 0 And CDbl(afterValue) <= 2147483647 Then afterId = CLng(afterValue)
End If

latestId = CurrentPostSequence()
Response.AddHeader "X-Latest-Post-Id", CStr(latestId)

If latestId > afterId Then
    ids = db.LRange(RedisKey("posts:global"), 0, -1)
    If IsArray(ids) Then
        For Each postId In ids
            If CLng(postId) <= afterId Then Exit For
            authorId = UserFieldFromPost(CStr(postId), "author_id")
            If authorId = currentUserId Or IsFollowing(currentUserId, authorId) Then
                Call RenderPost(CStr(postId), False)
            End If
        Next
    End If
End If

Call db.Close()
%>
