$post = Read-Host "Postname"
$post_path = "${post}/index.md"
hugo new posts/$post_path
code content/posts/$post_path