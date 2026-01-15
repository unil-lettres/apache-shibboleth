<!DOCTYPE html>
<html>
<head>
    <title>Home - Public</title>
    <style>
        body { font-family: sans-serif; margin: 40px; }
        .nav { margin-bottom: 20px; }
        .nav a { margin-right: 15px; padding: 5px 10px; background: #007bff; color: white; text-decoration: none; border-radius: 3px; }
        .info { background: #f0f0f0; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="nav">
        <a href="/">Home</a>
        <a href="/admin/">Admin (Protected)</a>
        <a href="/bob/">Bob (Protected)</a>
    </div>
    
    <h1>Welcome - Public Page</h1>
    <p>This page is accessible without authentication.</p>
    
    <div class="info">
        <h3>Test the setup:</h3>
        <ul>
            <li>This page (/) is public</li>
            <li>Click "Admin" or "Bob" to test Shibboleth protection</li>
            <li>You'll be redirected to SWITCHaai login</li>
        </ul>
    </div>
</body>
</html>
