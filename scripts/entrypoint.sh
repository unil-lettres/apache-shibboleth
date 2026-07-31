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
  echo "Configuring Shibboleth with Entity ID: $SHIB_HOSTNAME"
  
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

  # Check if Shibboleth certificates already exist
  if [[ -f /var/lib/shibboleth/sp-key.pem && -f /var/lib/shibboleth/sp-cert.pem ]]; then
    echo "Shibboleth certificates already exist. Existing certificates will not be modified."
  # Check if certificates are provided via environment variables
  elif [[ -n "$SHIB_SP_KEY" && -n "$SHIB_SP_CERT" ]]; then
    echo "Using Shibboleth certificates from environment variables..."
    # Check if the provided values are plaintext PEM or base64-encoded, and write them to files accordingly
    if [[ "$SHIB_SP_KEY" == *"-----BEGIN"* ]]; then
      printf '%s\n' "$SHIB_SP_KEY" > /var/lib/shibboleth/sp-key.pem
    else
      echo "Detected base64-encoded SHIB_SP_KEY, decoding..."
      printf '%s' "$SHIB_SP_KEY" | base64 -d > /var/lib/shibboleth/sp-key.pem
    fi
    if [[ "$SHIB_SP_CERT" == *"-----BEGIN"* ]]; then
      printf '%s\n' "$SHIB_SP_CERT" > /var/lib/shibboleth/sp-cert.pem
    else
      echo "Detected base64-encoded SHIB_SP_CERT, decoding..."
      printf '%s' "$SHIB_SP_CERT" | base64 -d > /var/lib/shibboleth/sp-cert.pem
    fi
    chmod 640 /var/lib/shibboleth/sp-key.pem
    chmod 644 /var/lib/shibboleth/sp-cert.pem
    echo "Certificates written from environment variables and permissions adjusted."
  # Generate new certificates if none exist
  else
    echo "Shibboleth key and certificate files missing. Generating new key and certificate for $ENTITY_ID entity ID"
    # shib-keygen may output chown errors which are harmless (files already have correct ownership)
    shib-keygen -f -h $ENTITY_ID -y 10 -o /var/lib/shibboleth 2>&1 | grep -v "chown:" || true
    # Adjust permissions so _shibd daemon can read the private key
    chmod 640 /var/lib/shibboleth/sp-key.pem
    chmod 644 /var/lib/shibboleth/sp-cert.pem
    echo "Certificates generated and permissions adjusted for _shibd access."
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

# Configure Shibboleth attributes forwarding as HTTP headers
if grep -q "__SHIB_HEADERS_BLOCK__" "/etc/apache2/sites-available/000-default.conf"; then
  
  # Determine which attributes to forward
  ATTRIBUTES_TO_FORWARD=""
  
  # Priority 1: SHIB_ATTRIBUTES environment variable (if set, even if empty)
  if [ -n "${SHIB_ATTRIBUTES+x}" ]; then
    ATTRIBUTES_TO_FORWARD="$SHIB_ATTRIBUTES"
    if [ -z "$SHIB_ATTRIBUTES" ]; then
      echo "SHIB_ATTRIBUTES is explicitly set to empty - no attributes will be forwarded."
    else
      echo "Using manually configured SHIB_ATTRIBUTES: $SHIB_ATTRIBUTES"
    fi
  
  # Priority 2: Auto-detection from metadata (if SHIB_RESOURCE_ID is set)
  elif [ -n "$SHIB_RESOURCE_ID" ]; then
    echo "SHIB_RESOURCE_ID is set to $SHIB_RESOURCE_ID - attempting auto-detection..."
    
    # Run Python script to extract attributes
    ATTRIBUTES_TO_FORWARD=$(/usr/local/bin/extract_attributes.py "$SHIB_RESOURCE_ID" "/etc/shibboleth/attribute-map.xml" 2>&1)
    EXTRACT_EXIT_CODE=$?
    
    if [ $EXTRACT_EXIT_CODE -eq 0 ]; then
      if [ -n "$ATTRIBUTES_TO_FORWARD" ]; then
        echo "Auto-detected attributes: $ATTRIBUTES_TO_FORWARD"
      else
        echo "WARNING: No attributes could be auto-detected from metadata."
      fi
    else
      echo "ERROR: Failed to extract attributes from metadata."
      echo "$ATTRIBUTES_TO_FORWARD" >&2
      ATTRIBUTES_TO_FORWARD=""
    fi
  
  # Priority 3: No configuration - no attributes forwarded
  else
    echo "Neither SHIB_ATTRIBUTES nor SHIB_RESOURCE_ID is set - no attributes will be forwarded."
    echo "Set SHIB_RESOURCE_ID for auto-detection or SHIB_ATTRIBUTES for manual configuration."
  fi
  
  # Generate RequestHeader directives
  HEADER_DIRECTIVES=""

  if [ -z "$ATTRIBUTES_TO_FORWARD" ]; then
    echo "No Shibboleth attributes will be forwarded as HTTP headers."
  else
    # Generate RequestHeader directives for each attribute
    IFS=',' read -ra ATTRS <<< "$ATTRIBUTES_TO_FORWARD"
    for attr in "${ATTRS[@]}"; do
      # Trim whitespace
      attr=$(echo "$attr" | xargs)

      # Convert attribute name to header format (replace underscores and hyphens)
      # Example: persistent-id becomes X-Shib-PersistentId
      header_name=$(echo "$attr" | sed 's/-\([a-z]\)/\U\1/g' | sed 's/_\([a-z]\)/\U\1/g' | sed 's/^\([a-z]\)/\U\1/')

      # "set" only overwrites the header when the attribute is in the session:
      # on an unprotected path, or when the IdP does not release the attribute,
      # a header forged by the client would otherwise reach the backend
      # untouched. "unset" first makes the header impossible to spoof.
      HEADER_DIRECTIVES+="    RequestHeader unset X-Shib-${header_name}\n"
      HEADER_DIRECTIVES+="    RequestHeader set X-Shib-${header_name} %{${attr}}e env=${attr}\n"
    done
  fi

  # Session properties (Shib-Identity-Provider, Shib-Authentication-Instant...)
  # are not attributes from attribute-map.xml: mod_shib exports them for every
  # authenticated session. Their name already starts with "Shib-", so the
  # header is the property prefixed with "X-" (X-Shib-Identity-Provider).
  # Only set default if variable is unset (not if explicitly set to empty string)
  if [ -z "${SHIB_SESSION_PROPERTIES+x}" ]; then
    SHIB_SESSION_PROPERTIES="Shib-Identity-Provider,Shib-Authentication-Instant,Shib-AuthnContext-Class"
  fi

  if [ -z "$SHIB_SESSION_PROPERTIES" ]; then
    echo "No Shibboleth session properties will be forwarded as HTTP headers."
  else
    echo "Forwarding Shibboleth session properties: $SHIB_SESSION_PROPERTIES"
    IFS=',' read -ra PROPS <<< "$SHIB_SESSION_PROPERTIES"
    for prop in "${PROPS[@]}"; do
      # Trim whitespace
      prop=$(echo "$prop" | xargs)

      HEADER_DIRECTIVES+="    RequestHeader unset X-${prop}\n"
      HEADER_DIRECTIVES+="    RequestHeader set X-${prop} %{${prop}}e env=${prop}\n"
    done
  fi

  # Replace placeholder with generated directives
  awk -v headers="$HEADER_DIRECTIVES" '{
    if ($0 ~ /__SHIB_HEADERS_BLOCK__/) {
      printf "%s", headers
    } else {
      print $0
    }
  }' "/etc/apache2/sites-available/000-default.conf" > /tmp/apache-headers.tmp
  mv /tmp/apache-headers.tmp "/etc/apache2/sites-available/000-default.conf"
else
  echo "Shibboleth headers already configured. No action needed."
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
