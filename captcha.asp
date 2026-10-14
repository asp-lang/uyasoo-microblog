<%@ Language=VBScript %>
<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
%>
<%
Response.ContentType = "image/svg+xml"
Response.AddHeader "Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"
Response.AddHeader "Pragma", "no-cache"
Response.AddHeader "X-Content-Type-Options", "nosniff"

Dim crypto
Dim code
Dim index
Dim x
Dim y
Dim x2
Dim y2
Dim size
Dim shade

Set crypto = Server.CreateObject("OpenASP.Crypto")
code = UCase(crypto.RandomHex(3))
Session("register_captcha") = code
Randomize Timer

Response.Write "<?xml version=""1.0"" encoding=""UTF-8""?>"
Response.Write "<svg xmlns=""http://www.w3.org/2000/svg"" width=""150"" height=""40"" viewBox=""0 0 150 40"" role=""img"" aria-label=""Verification code"">"
Response.Write "<rect width=""150"" height=""40"" rx=""4"" fill=""#f5f7fa""/>"

For index = 1 To 7
    x = Int(Rnd() * 150)
    y = Int(Rnd() * 40)
    x2 = Int(Rnd() * 150)
    y2 = Int(Rnd() * 40)
    shade = 35 + Int(Rnd() * 45)
    Response.Write "<line x1=""" & x & """ y1=""" & y & """ x2=""" & x2 & """ y2=""" & y2 & """ stroke=""hsl(" & shade & " 55% 58%)"" stroke-width=""1"" opacity="".65""/>"
Next

For index = 1 To 42
    x = Int(Rnd() * 150)
    y = Int(Rnd() * 40)
    size = 1 + Int(Rnd() * 2)
    shade = Int(Rnd() * 360)
    Response.Write "<circle cx=""" & x & """ cy=""" & y & """ r=""" & size & """ fill=""hsl(" & shade & " 38% 55%)"" opacity="".42""/>"
Next

For index = 1 To Len(code)
    x = 12 + ((index - 1) * 23)
    y = 27 + Int(Rnd() * 5) - 2
    Response.Write "<text class=""captcha-character"" x=""" & x & """ y=""" & y & """ transform=""rotate(" & (Int(Rnd() * 17) - 8) & " " & x & " " & y & ")"">" & Mid(code, index, 1) & "</text>"
Next

Response.Write "<path d=""M2 27 C34 10 67 37 101 20 S133 13 148 24"" fill=""none"" stroke=""#df6b35"" stroke-width=""1.5"" opacity="".7""/>"
Response.Write "<style>.captcha-character{font:700 22px Arial,sans-serif;fill:#263445;letter-spacing:0;user-select:none}</style></svg>"
%>
