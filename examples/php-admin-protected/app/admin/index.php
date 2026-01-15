<!DOCTYPE html>
<html>
<head>
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
                <td>Identity Provider</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_IDENTITY_PROVIDER'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Email (mail)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_MAIL'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Display Name</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_DISPLAYNAME'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Given Name</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_GIVENNAME'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>Surname (sn)</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_SN'] ?? 'Not set') ?></td>
            </tr>
            <tr>
                <td>EPPN</td>
                <td><?= htmlspecialchars($_SERVER['HTTP_X_SHIB_EPPN'] ?? 'Not set') ?></td>
            </tr>
        </table>
        
        <h3 style="margin-top: 20px;">All Shibboleth Headers:</h3>
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
