#! /bin/bash
sudo amazon-linux-extras install -y nginx1
sudo service nginx start
sudo rm /usr/share/nginx/html/index.html
sudo cat > /usr/share/nginx/html/index.html << 'WEBSITE'
<html>
<head>
    <title>MOO Team Server  - ${project} </title>
</head>
<body style=\"background-color:#1F778D\">
<p style=\"text-align: center;\">
    <span style=\"color:#FFFFFF;\">
        <span style=\"font-size:28px;\">You did it! Have a &#127790   -   ${project} ;</span>
    </span>
</p>
</body>
</html>
WEBSITE