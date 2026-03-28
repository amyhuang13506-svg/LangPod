#!/bin/bash
# LangPod Pipeline - Server Setup Script
# Run on Aliyun server (47.84.141.119)

set -e

echo "📦 Setting up LangPod Pipeline..."

# Create directory
sudo mkdir -p /opt/langpod/pipeline
sudo chown -R $USER:$USER /opt/langpod

# Copy pipeline files
# scp -r pipeline/* root@47.84.141.119:/opt/langpod/pipeline/

# Install Python dependencies
cd /opt/langpod/pipeline
pip3 install -r requirements.txt

# Create output and log directories
mkdir -p output logs

# Setup Nginx endpoint for episode list API
# Add to /etc/nginx/conf.d/langpod.conf:
cat << 'NGINX'
# === LangPod API (add to nginx config) ===
#
# location /langpod/api/episodes/ {
#     proxy_pass https://langpod.oss-ap-southeast-1.aliyuncs.com/episodes/;
#     proxy_set_header Host langpod.oss-ap-southeast-1.aliyuncs.com;
#     add_header Access-Control-Allow-Origin *;
# }
NGINX

# Setup cron job for daily generation
echo ""
echo "📅 Add this cron job:"
echo "   crontab -e"
echo "   0 3 * * * cd /opt/langpod/pipeline && python3 generate_daily.py >> logs/cron.log 2>&1"

echo ""
echo "✅ Setup complete!"
echo ""
echo "⚠️  Don't forget to:"
echo "   1. Fill in API keys in config.py"
echo "   2. Create OSS bucket 'langpod'"
echo "   3. Configure Nginx proxy"
echo "   4. Test with: python3 generate_daily.py easy"
