<?php
/**
 * GoXio Cloud Download & Upload Worker for Shared Hosting (PHP 7.4+)
 * 
 * Features:
 * - 0% Mobile Bandwidth: Downloads and uploads entirely using your hosting datacenter network
 * - Streamtape IP-Lock Bypass: Generates fresh tokens bound to your server IP to eliminate 403 errors
 * - Supports Google Drive (Multipart & Resumable), OneDrive (Personal & Business), and Telegram
 * - Real-time progress tracking via task JSON files
 * - Auto-cleans up temporary files after upload
 */

@ini_set('max_execution_time', 0);
@ini_set('memory_limit', '512M');
@set_time_limit(0);
ignore_user_abort(true);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$tasksDir = __DIR__ . '/tasks';
$tempDir = __DIR__ . '/tmp_downloads';

if (!file_exists($tasksDir)) {
    @mkdir($tasksDir, 0777, true);
}
if (!file_exists($tempDir)) {
    @mkdir($tempDir, 0777, true);
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

// --- 1. PING / TEST CONNECTION ---
if ($action === 'ping') {
    echo json_encode([
        'status' => 'ok',
        'server' => $_SERVER['SERVER_SOFTWARE'] ?? 'PHP Server',
        'php_version' => PHP_VERSION,
        'curl' => extension_loaded('curl'),
        'writeable' => is_writable($tasksDir) && is_writable($tempDir),
        'message' => 'GoXio Cloud Worker is ready!'
    ]);
    exit();
}

// --- DIAGNOSTIC ENDPOINT ---
if ($action === 'diag') {
    $testUrl = $_GET['url'] ?? $_POST['url'] ?? 'https://streamtape.com/';
    $ch = curl_init($testUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HEADER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
    $res = curl_exec($ch);
    $info = curl_getinfo($ch);
    curl_close($ch);
    echo json_encode([
        'http_code' => $info['http_code'],
        'effective_url' => $info['url'],
        'sample' => substr($res, 0, 1000)
    ]);
    exit();
}

// --- 2. GET TASK STATUS ---
if ($action === 'status') {
    $taskId = $_GET['task_id'] ?? $_POST['task_id'] ?? '';
    $taskId = preg_replace('/[^a-zA-Z0-9_-]/', '', $taskId);
    $taskFile = $tasksDir . '/' . $taskId . '.json';

    if (empty($taskId) || !file_exists($taskFile)) {
        http_response_code(404);
        echo json_encode(['status' => 'not_found', 'error' => 'Task not found']);
        exit();
    }

    $data = file_get_contents($taskFile);
    echo $data;
    exit();
}

// --- 3. START BACKGROUND CLOUD DOWNLOAD & UPLOAD ---
if ($action === 'start') {
    $rawInput = file_get_contents('php://input');
    $input = json_decode($rawInput, true) ?? $_POST;

    $url = $input['url'] ?? '';
    $provider = $input['provider'] ?? 'gdrive';
    $accessToken = $input['access_token'] ?? '';
    $filename = $input['filename'] ?? ('file_' . time() . '.mp4');
    $customHeaders = $input['headers'] ?? [];
    $chatId = $input['telegram_chat_id'] ?? '';

    if (empty($url)) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing target download URL']);
        exit();
    }

    $taskId = 'task_' . time() . '_' . substr(md5($url . microtime()), 0, 8);
    $taskFile = $tasksDir . '/' . $taskId . '.json';
    $cookieFile = $tempDir . '/cookie_' . $taskId . '.txt';

    $initialData = [
        'task_id' => $taskId,
        'filename' => $filename,
        'status' => 'downloading',
        'received_bytes' => 0,
        'total_bytes' => 0,
        'speed_bytes_sec' => 0,
        'progress' => 0.0,
        'started_at' => time(),
        'error' => null
    ];
    file_put_contents($taskFile, json_encode($initialData));

    // Fast response to client
    echo json_encode([
        'status' => 'started',
        'task_id' => $taskId,
        'message' => 'Task queued on shared hosting datacenter'
    ]);

    if (function_exists('fastcgi_finish_request')) {
        fastcgi_finish_request();
    } else {
        @ob_end_flush();
        @flush();
    }

    // --- BACKGROUND EXECUTION ---
    try {
        $safeName = preg_replace('/[\\\\\/:\*\?"<>\|]/', '_', $filename);
        $localFilePath = $tempDir . '/' . $taskId . '_' . $safeName;

        // Auto-resolve Streamtape IP-locked links on the server
        $downloadUrl = $url;
        $referer = 'https://streamtape.com/';

        if (isStreamtapeUrl($url)) {
            $resolved = resolveStreamtapeUrl($url, $cookieFile);
            $downloadUrl = $resolved['url'];
            $referer = $resolved['referer'];
        }

        // 1. Download file using cURL with live progress
        $fp = fopen($localFilePath, 'w+');
        if (!$fp) {
            throw new Exception("Unable to open local temporary file for writing");
        }

        $ch = curl_init($downloadUrl);
        curl_setopt($ch, CURLOPT_FILE, $fp);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_MAXREDIRS, 10);
        curl_setopt($ch, CURLOPT_TIMEOUT, 7200);
        curl_setopt($ch, CURLOPT_BUFFERSIZE, 128 * 1024);
        curl_setopt($ch, CURLOPT_NOPROGRESS, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
        curl_setopt($ch, CURLOPT_ENCODING, '');
        curl_setopt($ch, CURLOPT_COOKIEJAR, $cookieFile);
        curl_setopt($ch, CURLOPT_COOKIEFILE, $cookieFile);

        $reqHeaders = [
            'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Accept: */*',
            'Connection: keep-alive',
            'Referer: ' . $referer,
            'Range: bytes=0-',
            'Sec-Fetch-Dest: video',
            'Sec-Fetch-Mode: no-cors',
            'Sec-Fetch-Site: cross-site'
        ];

        if (!empty($customHeaders) && is_array($customHeaders)) {
            foreach ($customHeaders as $k => $v) {
                if (strtolower($k) !== 'referer') {
                    $reqHeaders[] = "$k: $v";
                }
            }
        }
        curl_setopt($ch, CURLOPT_HTTPHEADER, $reqHeaders);

        $lastUpdate = time();
        $lastBytes = 0;

        curl_setopt($ch, CURLOPT_PROGRESSFUNCTION, function($resource, $dltotal, $dlnow) use ($taskFile, $taskId, $filename, &$lastUpdate, &$lastBytes) {
            $now = microtime(true);
            if ($now - $lastUpdate >= 1.0) {
                $bytesDiff = $dlnow - $lastBytes;
                $timeDiff = max(0.1, $now - $lastUpdate);
                $speed = $bytesDiff / $timeDiff;

                $progress = ($dltotal > 0) ? round($dlnow / $dltotal, 4) : 0.0;

                $data = [
                    'task_id' => $taskId,
                    'filename' => $filename,
                    'status' => 'downloading',
                    'received_bytes' => (int)$dlnow,
                    'total_bytes' => (int)$dltotal,
                    'speed_bytes_sec' => round($speed),
                    'progress' => $progress,
                    'error' => null
                ];
                file_put_contents($taskFile, json_encode($data));

                $lastUpdate = $now;
                $lastBytes = $dlnow;
            }
        });

        $execResult = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        fclose($fp);

        if (!$execResult || ($httpCode !== 200 && $httpCode !== 206)) {
            // Fallback retry if 403 on resolved URL
            if ($httpCode === 403 && $downloadUrl !== $url) {
                $fp = fopen($localFilePath, 'w+');
                $ch = curl_init($url);
                curl_setopt($ch, CURLOPT_FILE, $fp);
                curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
                curl_setopt($ch, CURLOPT_TIMEOUT, 7200);
                curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
                curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
                curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
                curl_setopt($ch, CURLOPT_HTTPHEADER, [
                    'Accept: */*',
                    'Referer: https://streamtape.com/'
                ]);
                $execResult = curl_exec($ch);
                $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                curl_close($ch);
                fclose($fp);
            }
        }

        if (!$execResult || ($httpCode !== 200 && $httpCode !== 206)) {
            throw new Exception("Source download failed with HTTP code $httpCode");
        }

        // 2. Upload to Cloud Storage
        $fileSize = filesize($localFilePath);

        $uploadProgressData = [
            'task_id' => $taskId,
            'filename' => $filename,
            'status' => 'uploading_to_cloud',
            'received_bytes' => $fileSize,
            'total_bytes' => $fileSize,
            'speed_bytes_sec' => 0,
            'progress' => 0.9,
            'error' => null
        ];
        file_put_contents($taskFile, json_encode($uploadProgressData));

        $uploadSuccess = false;

        if ($provider === 'gdrive') {
            $uploadSuccess = uploadToGoogleDrive($localFilePath, $filename, $accessToken);
        } else if ($provider === 'onedrive' || $provider === 'onedrive_business' || $provider === 'onedrive_personal') {
            $uploadSuccess = uploadToOneDrive($localFilePath, $filename, $accessToken);
        } else if ($provider === 'telegram') {
            $uploadSuccess = uploadToTelegram($localFilePath, $filename, $accessToken, $chatId);
        }

        if (!$uploadSuccess) {
            throw new Exception("Cloud upload to $provider failed. Check token or storage quota.");
        }

        // 3. Cleanup temp files
        @unlink($localFilePath);
        @unlink($cookieFile);

        $completedData = [
            'task_id' => $taskId,
            'filename' => $filename,
            'status' => 'completed',
            'received_bytes' => $fileSize,
            'total_bytes' => $fileSize,
            'speed_bytes_sec' => 0,
            'progress' => 1.0,
            'completed_at' => time(),
            'error' => null
        ];
        file_put_contents($taskFile, json_encode($completedData));

    } catch (Exception $e) {
        if (isset($localFilePath) && file_exists($localFilePath)) {
            @unlink($localFilePath);
        }
        if (isset($cookieFile) && file_exists($cookieFile)) {
            @unlink($cookieFile);
        }
        $errorData = [
            'task_id' => $taskId,
            'filename' => $filename,
            'status' => 'failed',
            'error' => $e->getMessage()
        ];
        file_put_contents($taskFile, json_encode($errorData));
    }
    exit();
}

// --- STREAMTAPE RESOLVER ---

function isStreamtapeUrl($url) {
    return preg_match('/(?:streamtape|tapecontent|strcloud|strtape)\.(?:com|to|net|cloud|link)/i', $url);
}

function resolveStreamtapeUrl($url, $cookieFile) {
    $fileId = null;
    if (preg_match('/(?:\/e\/|\/v\/|\/get_video\/)([a-zA-Z0-9_-]+)/i', $url, $m)) {
        $fileId = $m[1];
    } else if (preg_match('/[?&]id=([a-zA-Z0-9_-]+)/i', $url, $m)) {
        $fileId = $m[1];
    }

    if (!$fileId) {
        return ['url' => $url, 'referer' => 'https://streamtape.com/'];
    }

    $embedUrl = "https://streamtape.com/e/$fileId";

    $ch = curl_init($embedUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_COOKIEJAR, $cookieFile);
    curl_setopt($ch, CURLOPT_COOKIEFILE, $cookieFile);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language: en-US,en;q=0.9',
    ]);
    $html = curl_exec($ch);
    $finalUrl = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL) ?: $embedUrl;
    curl_close($ch);

    if (empty($html)) {
        return ['url' => $url, 'referer' => $embedUrl];
    }

    // Match document.getElementById('robotlink').innerHTML = ...
    if (preg_match("/document\.getElementById\(['\"](?:robotlink|ideoolink|videolink|olink)['\"]\)\.innerHTML\s*=\s*['\"]([^'\"]+)['\"]\s*\+\s*(?:\(['\"]([^'\"]+)['\"]\)|['\"]([^'\"]+)['\"])/i", $html, $matches)) {
        $part1 = $matches[1];
        $part2 = !empty($matches[2]) ? $matches[2] : (!empty($matches[3]) ? $matches[3] : '');
        $extracted = $part1 . $part2;
        if (!preg_match('/^https?:/i', $extracted)) {
            $extracted = 'https:' . $extracted;
        }
        return ['url' => $extracted, 'referer' => $finalUrl];
    }

    // Match generic robotlink innerHTML
    if (preg_match("/document\.getElementById\(['\"]robotlink['\"]\)\.innerHTML\s*=\s*(.*?);/s", $html, $matches)) {
        $jsExpr = $matches[1];
        if (preg_match_all("/['\"]([^'\"]+)['\"]/", $jsExpr, $strMatches)) {
            $assembled = implode('', $strMatches[1]);
            if (!empty($assembled)) {
                if (!preg_match('/^https?:/i', $assembled)) {
                    $assembled = 'https:' . $assembled;
                }
                return ['url' => $assembled, 'referer' => $finalUrl];
            }
        }
    }

    // Match <div id="robotlink" style="display:none;">//streamtape.com/get_video?...</div>
    if (preg_match("/id=['\"]robotlink['\"][^>]*>([^<]+)<\/div>/i", $html, $matches)) {
        $link = trim($matches[1]);
        if (!preg_match('/^https?:/i', $link)) {
            $link = 'https:' . $link;
        }
        return ['url' => $link, 'referer' => $finalUrl];
    }

    return ['url' => $url, 'referer' => $embedUrl];
}

// --- CLOUD UPLOAD HELPERS ---

function uploadToGoogleDrive($filePath, $filename, $token) {
    $fileSize = filesize($filePath);

    if ($fileSize <= 5 * 1024 * 1024) {
        $metadata = json_encode(['name' => $filename]);
        $boundary = '-------' . md5(microtime());
        $delimiter = "\r\n--" . $boundary . "\r\n";
        $closeDelimiter = "\r\n--" . $boundary . "--";

        $body = $delimiter;
        $body .= "Content-Type: application/json; charset=UTF-8\r\n\r\n";
        $body .= $metadata;
        $body .= $delimiter;
        $body .= "Content-Type: application/octet-stream\r\n\r\n";
        $body .= file_get_contents($filePath);
        $body .= $closeDelimiter;

        $ch = curl_init('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "Authorization: Bearer $token",
            "Content-Type: multipart/related; boundary=$boundary",
            "Content-Length: " . strlen($body)
        ]);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ($code === 200 || $code === 201);
    }

    // Resumable upload for large files (> 5MB)
    $metadata = json_encode(['name' => $filename]);
    $ch = curl_init('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HEADER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "Authorization: Bearer $token",
        "Content-Type: application/json; charset=UTF-8",
        "X-Upload-Content-Length: $fileSize"
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $metadata);

    $response = curl_exec($ch);
    $headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    $headers = substr($response, 0, $headerSize);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        return false;
    }

    if (!preg_match('/location:\s*(.*)/i', $headers, $matches)) {
        return false;
    }
    $uploadUri = trim($matches[1]);
    if (empty($uploadUri)) return false;

    $chunkSize = 2 * 1024 * 1024; // 2 MB chunks
    $handle = fopen($filePath, 'rb');
    $uploaded = 0;
    $putCode = 0;

    while (!feof($handle) && $uploaded < $fileSize) {
        $chunk = fread($handle, $chunkSize);
        $chunkLen = strlen($chunk);
        if ($chunkLen === 0) break;
        $end = $uploaded + $chunkLen - 1;

        $ch = curl_init($uploadUri);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
        curl_setopt($ch, CURLOPT_POSTFIELDS, $chunk);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "Content-Length: $chunkLen",
            "Content-Range: bytes $uploaded-$end/$fileSize"
        ]);
        $res = curl_exec($ch);
        $putCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($putCode !== 200 && $putCode !== 201 && $putCode !== 308) {
            fclose($handle);
            return false;
        }
        $uploaded += $chunkLen;
    }
    fclose($handle);

    return ($putCode === 200 || $putCode === 201);
}

function uploadToOneDrive($filePath, $filename, $token) {
    $fileSize = filesize($filePath);
    $encodedName = rawurlencode($filename);

    if ($fileSize <= 4 * 1024 * 1024) {
        $directUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/content";
        $fp = fopen($filePath, 'r');
        $ch = curl_init($directUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_PUT, true);
        curl_setopt($ch, CURLOPT_INFILE, $fp);
        curl_setopt($ch, CURLOPT_INFILESIZE, $fileSize);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "Authorization: Bearer $token",
            "Content-Type: application/octet-stream"
        ]);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        fclose($fp);
        return ($code === 200 || $code === 201);
    }

    // Upload session with 320 KiB chunks
    $sessionUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/createUploadSession";
    $ch = curl_init($sessionUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
        'item' => ['@microsoft.graph.conflictBehavior' => 'rename']
    ]));
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "Authorization: Bearer $token",
        "Content-Type: application/json"
    ]);
    $res = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) return false;

    $sessionData = json_decode($res, true);
    $uploadUrl = $sessionData['uploadUrl'] ?? '';
    if (empty($uploadUrl)) return false;

    $chunkSize = 320 * 1024 * 10; // 3.2 MB
    $handle = fopen($filePath, 'rb');
    $uploaded = 0;

    while (!feof($handle) && $uploaded < $fileSize) {
        $chunk = fread($handle, $chunkSize);
        $chunkLen = strlen($chunk);
        $end = $uploaded + $chunkLen - 1;

        $ch = curl_init($uploadUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
        curl_setopt($ch, CURLOPT_POSTFIELDS, $chunk);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "Content-Length: $chunkLen",
            "Content-Range: bytes $uploaded-$end/$fileSize"
        ]);
        $chunkRes = curl_exec($ch);
        $cCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($cCode !== 200 && $cCode !== 201 && $cCode !== 202) {
            fclose($handle);
            return false;
        }
        $uploaded += $chunkLen;
    }
    fclose($handle);
    return true;
}

function uploadToTelegram($filePath, $filename, $botToken, $chatId) {
    if (empty($botToken)) return false;
    $targetChat = !empty($chatId) ? $chatId : 'me';

    $ch = curl_init("https://api.telegram.org/bot$botToken/sendDocument");
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    $cFile = new CURLFile($filePath, mime_content_type($filePath) ?: 'application/octet-stream', $filename);
    curl_setopt($ch, CURLOPT_POSTFIELDS, [
        'chat_id' => $targetChat,
        'document' => $cFile
    ]);

    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return ($code === 200);
}
