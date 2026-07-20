!/bin/bash

# Database Configuration
DB_NAME="acore_monitoring"

# Fetch the most recent row in vertical format (\G) using socket authentication
while IFS=':' read -r key value; do
    # Trim leading/trailing whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    # Ignore header/footer lines from mysql output
    if [[ -n "$key" && "$key" != "*"* ]]; then
        # Dynamically set the variable with the column name
        declare "$key"="$value"
    fi
done < <(/usr/bin/mysql -D "$DB_NAME" -e "SELECT * FROM memory_log ORDER BY id DESC LIMIT 1 \G" 2>/dev/null)

# Verify the variables are populated
echo "Successfully loaded entry ID: ${id} at ${timestamp}"
echo "Worldserver RSS: ${worldserver_rss_mb} MB | Online Players: ${characters_online}"

bash ~/notify.sh "memory" "📊 **Hourly check** (${timestamp}): ${available_mb}MB available, worldserver RSS ${worldserver_rss_mb}MB, ${characters_online} online"
