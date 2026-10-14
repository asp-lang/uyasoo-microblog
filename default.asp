<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<!--#include file="config.asp" -->
<!--#include file="lib.asp" -->
<%
Response.ContentType = "text/html"

Set db = Server.CreateObject("OpenASP.Redis")
Call db.Open(REDIS_CONNECTION)
Set crypto = Server.CreateObject("OpenASP.Crypto")

currentUserId = ResolveCurrentUser()

Call HandleAction(FormValue("action"))

Dim viewName
Dim profileId
Dim pageTitle
viewName = LCase(QueryValue("view"))
If viewName = "" Then viewName = "home"
pageTitle = APP_NAME
If viewName = "auth" Then pageTitle = "Sign in - " & APP_NAME
If viewName = "discover" Then pageTitle = "Discover - " & APP_NAME
If viewName = "topics" Then pageTitle = "Topics - " & APP_NAME
If viewName = "topic" Then pageTitle = "Topic - " & APP_NAME
If viewName = "search" Then pageTitle = "Search - " & APP_NAME
If viewName = "settings" Then pageTitle = "Settings - " & APP_NAME
%>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="theme-color" content="#ffffff">
    <title><%= Html(pageTitle) %></title>
    <link rel="icon" type="image/svg+xml" href="assets/favicon.svg?v=<%= ASSET_VERSION %>">
    <link rel="stylesheet" href="assets/app.css?v=<%= ASSET_VERSION %>">
</head>
<body>
    <% If Not (viewName = "auth" And currentUserId = "") Then %>
    <header class="topbar">
        <div class="topbar-inner">
            <a class="brand" href="<%= APP_BASE_PATH %>" aria-label="<%= APP_NAME %> home">
                <span class="brand-mark">Y</span>
                <span><%= APP_NAME %></span>
            </a>
            <form class="top-search" method="get">
                <input type="hidden" name="view" value="search">
                <label>
                    <span class="sr-only">Search people</span>
                    <input name="q" placeholder="Search uYasoo" value="<%= Html(QueryValue("q")) %>">
                </label>
            </form>
            <nav class="account-nav" aria-label="Account">
                <% If currentUserId <> "" Then %>
                    <a href="<%= ProfilePath(currentUserId) %>"><%= Html(UserDisplayName(currentUserId)) %></a>
                    <form method="post">
                        <input type="hidden" name="action" value="logout">
                        <input type="hidden" name="csrf" value="<%= Html(CsrfToken()) %>">
                        <button type="submit">Sign out</button>
                    </form>
                <% Else %>
                    <a class="button button-primary button-small" href="<%= APP_BASE_PATH %>?view=auth">Sign in</a>
                <% End If %>
            </nav>
        </div>
    </header>
    <% End If %>

    <main>
        <% Call RenderFlash() %>
        <% If viewName = "auth" And currentUserId = "" Then %>
            <% Call RenderAccountPanel() %>
        <% Else %>
            <div class="app-grid">
                <% Call RenderLeftNavigation(viewName) %>
                <section class="content-column">
                    <%
                    Select Case viewName
                        Case "home"
                            If currentUserId <> "" Then
                                Response.Write "<div class=""page-heading""><h1>Home</h1><span>Your network</span></div>"
                                Call RenderComposer()
                                Response.Write "<button id=""feed-update-bar"" class=""feed-update-bar"" type=""button"" data-after=""" & CurrentPostSequence() & """ hidden>"
                                Response.Write "<span class=""feed-update-label"">New posts available</span><span class=""feed-update-count"" aria-hidden=""true""></span></button>"
                            Else
                                Response.Write "<section class=""welcome-strip""><div><h1>See what people are sharing.</h1><p>Create an account to build your own timeline.</p></div><a class=""button button-primary"" href=""" & APP_BASE_PATH & "?view=auth"">Join uYasoo</a></section>"
                                Response.Write "<div class=""page-heading""><h1>Latest</h1><span>Public posts</span></div>"
                            End If
                            Call RenderFeed("home", "")
                        Case "discover"
                            Response.Write "<div class=""page-heading""><h1>Discover</h1><span>Latest across uYasoo</span></div>"
                            Call RenderFeed("discover", "")
                        Case "topics"
                            Call RenderTopics()
                        Case "topic"
                            Call RenderTopic(QueryValue("name"))
                        Case "profile"
                            profileId = QueryValue("id")
                            If profileId = "" Then profileId = currentUserId
                            If UserExists(profileId) Then
                                Call RenderProfileHeader(profileId)
                                Call RenderFeed("profile", profileId)
                            Else
                                Response.Status = "404 Not Found"
                                Response.Write "<div class=""empty-state""><strong>Account not found</strong><span>The profile may have been removed.</span></div>"
                            End If
                        Case "followers"
                            profileId = QueryValue("id")
                            If UserExists(profileId) Then
                                Call RenderPeopleList("followers", profileId)
                            Else
                                Response.Status = "404 Not Found"
                                Response.Write "<div class=""empty-state""><strong>Account not found</strong></div>"
                            End If
                        Case "following"
                            profileId = QueryValue("id")
                            If UserExists(profileId) Then
                                Call RenderPeopleList("following", profileId)
                            Else
                                Response.Status = "404 Not Found"
                                Response.Write "<div class=""empty-state""><strong>Account not found</strong></div>"
                            End If
                        Case "post"
                            profileId = QueryValue("id")
                            If db.Exists(PostKey(profileId)) Then
                                Response.Write "<div class=""page-heading""><h1>Post</h1><span>Conversation</span></div>"
                                Call RenderPost(profileId, True)
                            Else
                                Response.Status = "404 Not Found"
                                Response.Write "<div class=""empty-state""><strong>Post not found</strong><span>It may have been deleted.</span></div>"
                            End If
                        Case "search"
                            Call RenderSearch(QueryValue("q"))
                        Case "settings"
                            Call RequireAuth()
                            Call RenderSettings()
                        Case "auth"
                            Call RedirectTo(APP_BASE_PATH)
                        Case Else
                            Response.Status = "404 Not Found"
                            Response.Write "<div class=""empty-state""><strong>Page not found</strong><span>Use the navigation to continue.</span></div>"
                    End Select
                    %>
                </section>
                <% Call RenderRightRail() %>
            </div>
        <% End If %>
    </main>
    <footer class="powered-footer">Powered By OpenASP.dev</footer>
    <script src="assets/app.js?v=<%= ASSET_VERSION %>"></script>
</body>
</html>
<%
Call db.Close()
%>
