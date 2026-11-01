# 手势 UDP 模拟器：每 100ms 向 127.0.0.1:9876 发送随机手势状态包（暂定格式，T30 定稿后同步）
# 用法：powershell -File tools\udp_simulator.ps1 [-Port 9876] [-Seconds 30]
param([int]$Port = 9876, [int]$Seconds = 30)
$gestures = @("open", "ok", "fist", "point", "three", "flip")
$udp = New-Object System.Net.Sockets.UdpClient
$bytes_ep = [Text.Encoding]::UTF8
$end = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $Port)
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    $obj = [ordered]@{
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0
        left  = @{ gesture = (Get-Random $gestures); confidence = [math]::Round((Get-Random -Minimum 0.6 -Maximum 1.0), 2); pos = @(0.3, 0.5) }
        right = @{ gesture = (Get-Random $gestures); confidence = [math]::Round((Get-Random -Minimum 0.6 -Maximum 1.0), 2); pos = @(0.7, 0.5) }
    }
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    $buf = $bytes_ep.GetBytes($json)
    $udp.Send($buf, $buf.Length, $end) | Out-Null
    Start-Sleep -Milliseconds 100
}
$udp.Close()
Write-Output "simulator done"
