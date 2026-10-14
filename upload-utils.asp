<%
' Copyright (c) 2026 https://uyasoo.com
' SPDX-License-Identifier: MIT
Function BinaryToText(data)
    Dim result
    Dim index
    result = ""
    For index = 1 To LenB(data)
        result = result & Chr(AscB(MidB(data, index, 1)))
    Next
    BinaryToText = result
End Function

Function BinaryUtf8ToText(data)
    Dim stream
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.Write data
    stream.Position = 0
    stream.Type = 2
    stream.Charset = "utf-8"
    BinaryUtf8ToText = stream.ReadText
    stream.Close
    Set stream = Nothing
End Function

Function HeaderParameter(headers, parameterName)
    Dim marker
    Dim startAt
    Dim endAt
    marker = parameterName & "=" & Chr(34)
    startAt = InStr(1, headers, marker, 1)
    If startAt = 0 Then
        HeaderParameter = ""
        Exit Function
    End If
    startAt = startAt + Len(marker)
    endAt = InStr(startAt, headers, Chr(34), 0)
    If endAt = 0 Then
        HeaderParameter = ""
    Else
        HeaderParameter = Mid(headers, startAt, endAt - startAt)
    End If
End Function

Function ImageExtension(data)
    ImageExtension = ""
    If LenB(data) >= 3 Then
        If AscB(MidB(data, 1, 1)) = &HFF And AscB(MidB(data, 2, 1)) = &HD8 And AscB(MidB(data, 3, 1)) = &HFF Then
            ImageExtension = "jpg"
            Exit Function
        End If
    End If
    If LenB(data) >= 8 Then
        If AscB(MidB(data, 1, 1)) = &H89 And AscB(MidB(data, 2, 1)) = &H50 And AscB(MidB(data, 3, 1)) = &H4E And AscB(MidB(data, 4, 1)) = &H47 And AscB(MidB(data, 5, 1)) = &H0D And AscB(MidB(data, 6, 1)) = &H0A And AscB(MidB(data, 7, 1)) = &H1A And AscB(MidB(data, 8, 1)) = &H0A Then
            ImageExtension = "png"
            Exit Function
        End If
    End If
    If LenB(data) >= 12 Then
        If BinaryToText(MidB(data, 1, 4)) = "RIFF" And BinaryToText(MidB(data, 9, 4)) = "WEBP" Then
            ImageExtension = "webp"
        End If
    End If
End Function
%>
