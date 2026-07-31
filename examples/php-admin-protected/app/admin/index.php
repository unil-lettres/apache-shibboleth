<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Admin - Protected</title>
    <style>
        body { font-family: sans-serif; margin: 40px; }
        .nav { margin-bottom: 20px; }
        .nav a { margin-right: 15px; padding: 5px 10px; background: #007bff; color: white; text-decoration: none; border-radius: 3px; }
        .success { background: #d4edda; padding: 15px; border-radius: 5px; border: 1px solid #c3e6cb; }
        .attributes { background: #f8f9fa; padding: 15px; margin-top: 20px; border-radius: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #e9ecef; }
    </style>
</head>
<body>
    <div class="nav">
        <a href="/">Home</a>
        <a href="/admin/">Admin (Protected)</a>
    </div>
    
    <div class="success">
        <h1>✓ Admin Area - Protected by Shibboleth</h1>
        <p>You successfully authenticated via Shibboleth!</p>
    </div>
    
    <div class="attributes">
        <h2>Shibboleth Attributes Received:</h2>
        <table>
            <tr>
                <th>Attribute</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>Email (mail)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_MAIL'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Given Name (givenName)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_GIVENNAME'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Surname (surname)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_SURNAME'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Unique ID (uniqueID)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_UNIQUEID'] ?? 'Not set') ?></td>
            </tr>
        </table>

        <p>These are the attributes listed in <code>SHIB_ATTRIBUTES</code>. Only those are set - and stripped from incoming requests - by the proxy.</p>
        
        <h3 style="margin-top: 20px;">All X-Shib-* headers as received:</h3>
        <p>Raw dump, including any header the client sent itself. Only the attributes above are guaranteed to come from Shibboleth.</p>
        <pre style="background: white; padding: 10px; border: 1px solid #ddd; overflow: auto; max-height: 300px;">
<?php
foreach (getallheaders() as $name => $value) {
    if (stripos($name, 'shib') !== false || stripos($name, 'x-shib') === 0) {
        echo htmlspecialchars("$name: $value\n");
    }
}
?>
        </pre>
    </div>
</body>
</html>
