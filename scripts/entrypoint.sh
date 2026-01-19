#!/bin/bash
set -e

echo "Starting Apache with Shibboleth configuration..."

# Use SHIB_ENTITY_ID if set, otherwise use SHIB_HOSTNAME
if [ -n "$SHIB_ENTITY_ID" ]; then
  ENTITY_ID="$SHIB_ENTITY_ID"
else
  ENTITY_ID="$SHIB_HOSTNAME"
fi

# Check if SHIB_HOSTNAME and SHIB_CONTACT are set
if [ -n "$SHIB_HOSTNAME" ] && [ -n "$SHIB_CONTACT" ]; then
  echo "Configuring Shibboleth with hostname: $SHIB_HOSTNAME"
  echo "Using Entity ID: $ENTITY_ID"
  
  # Update Shibboleth main configuration file (shibboleth2.xml)
  if grep -q "__HOSTNAME__" "/etc/shibboleth/shibboleth2.xml"; then
    # Replace hostname placeholder with ENTITY_ID
    sed -i "s|__HOSTNAME__|$ENTITY_ID|g" "/etc/shibboleth/shibboleth2.xml"
    echo "Replaced hostname placeholder with $ENTITY_ID in Shibboleth configuration."

    # Replace contact email placeholder
    sed -i "s|__CONTACT__|$SHIB_CONTACT|g" "/etc/shibboleth/shibboleth2.xml"
    echo "Replaced contact email placeholder in Shibboleth configuration."
    
    # Replace target URL placeholder
    SHIB_RETURN_URL="${SHIB_RETURN_URL:-/}"
    sed -i "s|__TARGET_URL__|https://$SHIB_HOSTNAME$SHIB_RETURN_URL|g" "/etc/shibboleth/shibboleth2.xml"
    echo "Configured Shibboleth return URL: https://$SHIB_HOSTNAME$SHIB_RETURN_URL"
  else
    echo "Shibboleth already configured. No action needed."
  fi

  # Check if Shibboleth key or certificate file exists, if not generate them
  if [[ ! -f /var/lib/shibboleth/sp-key.pem && ! -f /var/lib/shibboleth/sp-cert.pem ]]; then
    echo "Shibboleth key and certificate files missing. Generating new key and certificate for $ENTITY_ID entity ID"
    shib-keygen -f -u _shibd -h $ENTITY_ID -y 10 -o /var/lib/shibboleth
  else
    echo "Shibboleth key and certificate files already exist. No action needed."
  fi

  # Update Apache configuration file (000-default.conf)
  if grep -q "__SERVER_NAME__" "/etc/apache2/sites-available/000-default.conf"; then
      sed -i "s|__SERVER_NAME__|https://$SHIB_HOSTNAME:443|g" "/etc/apache2/sites-available/000-default.conf"
      echo "Replaced ServerName by $SHIB_HOSTNAME in Apache configuration."
  else
    echo "Apache ServerName already configured. No action needed."
  fi

else
  echo "WARNING: SHIB_HOSTNAME and SHIB_CONTACT environment variables are not set."
  echo "Shibboleth and Apache2 will not be properly configured. Please set these variables to enable Shibboleth."
fi

# Configure Shibboleth protected paths
if grep -q "__SHIB_PROTECTED_PATHS_BLOCK__" "/etc/apache2/sites-available/000-default.conf"; then
  # Only set default if variable is unset (not if explicitly set to empty string)
  if [ -z "${SHIB_PROTECTED_PATHS+x}" ]; then
    SHIB_PROTECTED_PATHS="/"
  fi
  
  if [ -z "$SHIB_PROTECTED_PATHS" ]; then
    echo "SHIB_PROTECTED_PATHS is empty - no automatic Shibboleth protection configured."
    echo "You can configure Shibboleth protection manually in your custom Apache configuration."
    # Remove the placeholder
    sed -i "/__SHIB_PROTECTED_PATHS_BLOCK__/d" "/etc/apache2/sites-available/000-default.conf"
    echo "Removed Shibboleth protection placeholder from Apache configuration."
  else
    # Generate Location blocks for each protected path
    LOCATION_BLOCKS=""
    IFS=',' read -ra PATHS <<< "$SHIB_PROTECTED_PATHS"
    for path in "${PATHS[@]}"; do
      # Trim whitespace
      path=$(echo "$path" | xargs)
      
      # Build authorization rules
      if [ -n "$SHIB_ALLOWED_USERS" ]; then
        # Restrict access to specific users by uniqueID
        AUTH_RULES=""
        IFS=',' read -ra USERS <<< "$SHIB_ALLOWED_USERS"
        for user in "${USERS[@]}"; do
          user=$(echo "$user" | xargs)
          AUTH_RULES+="        Require shib-attr uniqueID $user\n"
        done
        
        LOCATION_BLOCKS+="    <Location $path>
        AuthType shibboleth
        ShibRequestSetting requireSession true
$AUTH_RULES    </Location>
"
      else
        # Default: allow any valid authenticated user
        LOCATION_BLOCKS+="    <Location $path>
        AuthType shibboleth
        ShibRequestSetting requireSession true
        Require valid-user
    </Location>
"
      fi
    done
    
    # Replace placeholder with generated blocks
    awk -v blocks="$LOCATION_BLOCKS" '{
      if ($0 ~ /__SHIB_PROTECTED_PATHS_BLOCK__/) {
        printf "%s", blocks
      } else {
        print $0
      }
    }' "/etc/apache2/sites-available/000-default.conf" > /tmp/apache-vhost.tmp
    mv /tmp/apache-vhost.tmp "/etc/apache2/sites-available/000-default.conf"
    echo "Configured Shibboleth protection for: $SHIB_PROTECTED_PATHS"
  fi
else
  echo "Shibboleth protection already configured. No action needed."
fi

# Configure custom Apache directives from environment variable
if [ -n "$APACHE_CUSTOM_CONFIG" ]; then
  echo "Applying custom Apache configuration from APACHE_CUSTOM_CONFIG..."
  mkdir -p /etc/apache2/vhost.d
  echo "$APACHE_CUSTOM_CONFIG" > /etc/apache2/vhost.d/custom-from-env.conf
  echo "Custom Apache configuration applied to custom-from-env.conf."
fi

echo "Starting services..."

# Execute the command passed to the entrypoint
exec "$@"
