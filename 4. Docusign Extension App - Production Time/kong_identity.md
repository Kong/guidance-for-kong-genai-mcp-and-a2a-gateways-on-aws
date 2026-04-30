# Docusign Extension App - Production Time

Now, let's promote the **Extension App** to Production. That means we are going to add new components to our deployments:
* Actual Data IO Services will be deployed so we can remove the **Kong Mocking Plugin**
* Configure **Kong Identity** to play the Identity Provider role and implement the **Client Credentials Grant**
* Configure the **Extension App** to integration with **Kong Identity**

Here's the new architecture

<img src="../static/images/architecture2.png">

## Kong Identity

### Create the Authorization Server in Kong Identity

Before you can configure the **OpenId Connect** plugin, you must first create an **Authorization Server** in **Kong Identity**. The AuthZ Server name is unique per each organization and each Konnect region. We are going to use the [Kong Identity REST Admin APIs](https://developer.konghq.com/api/konnect/kong-identity) to do it. Make sure you still have the ``PAT`` environment variable set.

Create an auth server using the [``/v1/auth-servers``](https://developer.konghq.com/api/konnect/kong-identity/v1/#/operations/createAuthServer) endpoint. Note each AuthN Server has an audience specified.

```
curl -sX POST "https://us.api.konghq.com/v1/auth-servers" \
  -H "Authorization: Bearer $PAT"\
  -H "Content-Type: application/json" \
  --json '{
    "name": "AuthZ_Server_1",
    "audience": "http://kong.dev",
    "description": "AuthZ Server 1"
  }' | jq
```

You should get a response like this:

```
{
  "audience": "http://kong.dev",
  "created_at": "2026-02-17T17:42:23.194606Z",
  "description": "AuthZ Server 1",
  "id": "f5db888d-14d7-4f63-xxxx-xxxxxxxxx",
  "issuer": "https://xxxxxx.us.identity.konghq.com/auth",
  "labels": {},
  "metadata_uri": "https://xxxxxx.us.identity.konghq.com/auth/.well-known/openid-configuration",
  "name": "AuthZ_Server_1",
  "signing_algorithm": "RS256",
  "trusted_origins": [],
  "updated_at": "2026-02-17T17:42:23.194606Z"
}
```

##### Check your AuthZ Server

```
curl -sX GET "https://us.api.konghq.com/v1/auth-servers" \
  -H "Authorization: Bearer $PAT" | jq
```

Get the AuthZ Server Id:


```
export AUTHZ_SERVER_ID=$(curl -sX GET "https://us.api.konghq.com/v1/auth-servers" -H "Authorization: Bearer $PAT" | jq -r '.data[0].id')
```

Get the Issuer URL:

```
export ISSUER_URL=$(curl -sX GET "https://us.api.konghq.com/v1/auth-servers" -H "Authorization: Bearer $PAT" | jq -r '.data[0].issuer')
```



### Configure the AuthZ server with scopes

Configure a scope in your auth server using the [``/v1/auth-servers/$AUTHZ_SERVER_ID/scopes``](https://developer.konghq.com/api/konnect/kong-identity/v1/#/operations/createAuthServerScope) endpoint:

```
curl -sX POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/scopes" \
  -H "Authorization: Bearer $PAT"\
  -H "Content-Type: application/json" \
  --json '{
    "name": "scope1",
    "description": "scope1",
    "default": false,
    "include_in_metadata": false,
    "enabled": true
  }' | jq
```

Expected response

```
{
  "created_at": "2026-02-17T17:44:20.009421Z",
  "default": false,
  "description": "scope1",
  "enabled": true,
  "id": "316b6d43-55db-4083-xxxx-xxxxxxxxxx",
  "include_in_metadata": false,
  "name": "scope1",
  "updated_at": "2026-02-17T17:44:20.009421Z"
}
```

Export your scope ID:

```
export SCOPE_ID=$(curl -sX GET "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/scopes" -H "Authorization: Bearer $PAT" | jq -r '.data[0].id')
```



### Configure the AuthZ server with custom claims

Configure a custom claim using the [``/v1/auth-servers/$AUTHZ_SERVER_ID/claims``](https://developer.konghq.com/api/konnect/kong-identity/v1/#/operations/createAuthServerClaim) endpoint. A custom claim can be include in the tokens or inside a scope.


```
curl -sX POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/claims" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  --json '{
    "name": "claim1",
    "value": "claim1",
    "include_in_token": true,
    "include_in_all_scopes": false,
    "include_in_scopes": [
      "'$SCOPE_ID'"
    ],
    "enabled": true
  }' | jq
```

Expected output:

```
{
  "created_at": "2026-02-17T17:45:27.788763Z",
  "enabled": true,
  "id": "c74de2c0-7dcd-448f-xxxx-xxxxxxxxx",
  "include_in_all_scopes": false,
  "include_in_scopes": [
    "316b6d43-55db-4083-aec2-f975c15fcbd1"
  ],
  "include_in_token": true,
  "name": "claim1",
  "updated_at": "2026-02-17T17:45:27.788763Z",
  "value": "claim1"
}
```

### Create a client in the AuthZ Server

The client is the machine-to-machine credential. In this tutorial, Konnect will autogenerate the **Client ID** and **Client Secret**, but you can alternatively specify one yourself.

Configure the client using the [``/v1/auth-servers/$AUTHZ_SERVER_ID/clients``](https://developer.konghq.com/api/konnect/kong-identity/v1/#/operations/createAuthServerClient) endpoint. Note the the Access Token duration has a timeout of 60 seconds:

```
curl -sX POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/clients" \
  -H "Authorization: Bearer $PAT"\
  -H "Content-Type: application/json" \
  --json '{
    "name": "client1",
    "grant_types": [
      "client_credentials"
    ],
    "allow_all_scopes": false,
    "allow_scopes": [
      "'$SCOPE_ID'"
    ],
    "access_token_duration": 60,
    "id_token_duration": 60,
    "response_types": [
      "id_token",
      "token"
    ]
  }' | jq
```

Expected output:

```
{
  "access_token_duration": 60,
  "allow_all_scopes": false,
  "allow_scopes": [
    "316b6d43-55db-4083-aec2-f975c15fcbd1"
  ],
  "client_secret": "<secret>",
  "created_at": "2026-02-17T17:47:21.073803Z",
  "grant_types": [
    "client_credentials"
  ],
  "id": "<id>",
  "id_token_duration": 60,
  "labels": {},
  "login_uri": null,
  "name": "client1",
  "redirect_uris": [],
  "response_types": [
    "id_token",
    "token"
  ],
  "token_endpoint_auth_method": "client_secret_post",
  "updated_at": "2026-02-17T17:47:21.073803Z"
}
```

The Client Secret will not be shown again, so copy both ID and Secret:

```
export CLIENT_ID=<YOUR_CLIENT_ID>
export CLIENT_SECRET=<YOUR_CLIENT_SECRET>
```


## Checking you Kong Identity Authorization Server

Kong Identity provides the standard endpoint ```$ISSUER_URL/.well-known/openid-configuration``` where you can get these and several other Kong Identity configuration parameters.


```
curl -s $ISSUER_URL/.well-known/openid-configuration | jq
```


### Kong Identity User Interface

You can also check the Konnect UI with your Authorization Server and its Clients, Scopes and Claims defined:

<img src="../static/images/kong_identity.png">






## Kong OpenId Connect Plugin

The [Kong OpenId Connect Plugin](https://developer.konghq.com/plugins/openid-connect/) is used to implement the **OAuth2 Client Credentials Grant** between the **Docusign Extension App** and **Kong API Gateway** itself. The **decK** declaration has been updated to add the plugin. The new file can be found [here](../kong_docusign_openid_mock.yaml)


The declaration applies the Plugin to the existing **Kong Route**, implementing the **Introspection Flow** to validate the Token issued by **Kong Identity** and injected to the Request by **Docusign Extension App**. Here's the new snippet:

```
routes:
- name: docusign-route
  paths:
  - /
  plugins:
  - name: openid-connect
    instance_name: openid-connect-docusign-kong-identity
    enabled: true
    config:
      issuer: ${{ env "DECK_ISSUER" }}
      client_id:
      - ${{ env "DECK_CLIENT_ID" }}
      client_secret:
      - ${{ env "DECK_CLIENT_SECRET" }}
      auth_methods:
      - introspection
      introspection_endpoint: ${{ env "DECK_KONG_IDENTITY_INTROSPECTION_URL" }}
```



### Submit the decK declaration to your Control Plane

Before submiting the new declaration we have set the decK environment variables:

```
export DECK_ISSUER=$ISSUER_URL
export DECK_KONG_IDENTITY_INTROSPECTION_URL=$ISSUER_URL/introspect
export DECK_CLIENT_ID=$CLIENT_ID
export DECK_CLIENT_SECRET=$CLIENT_SECRET
```


```
deck gateway reset --konnect-control-plane-name kong-aws --konnect-token $PAT -f
deck gateway sync --konnect-control-plane-name kong-aws --konnect-token $PAT kong_docusign_openid_mock.yaml
```



### Exploring the Token and Introspection Endpoints

To exercise the Introspection Endpoint, let's send some requests to Kong Identity, acting as the Consumer and the Gateway.

#### Token Endpoint

In the first request, we play the Consumer role, using the [**Client Credentials Grant**](https://oauth.net/2/grant-types/client-credentials/) to get our Access Token

```
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=scope1" | jq -r '.access_token')
```



You can decode the Access Token with:

```
echo $TOKEN | jwt decode -
```

You should get an output like this. The ``sub`` field represents the same ``client_id``.

```
Token header
------------
{
  "typ": "JWT",
  "alg": "RS256",
  "kid": "0c6b4da3-e954-43fb-b435-29df04f40bdf"
}

Token claims
------------
{
  "aud": [
    "http://kong.dev"
  ],
  "claim1": "claim1",
  "client_id": "xxxxxx",
  "exp": 1771350984,
  "iat": 1771350924,
  "iss": "https://xxxxxxxx.us.identity.konghq.com/auth",
  "jti": "019c6cbe-1de8-7bb4-b1a4-85c5864a1eb0",
  "nbf": 1771350924,
  "scope": "scope1",
  "sub": "p4aih3vylfgl3d8a"
}
```



You can check all tokens issued by a given Client ID:
```
curl -sX GET "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/clients/$CLIENT_ID/tokens" -H "Authorization: Bearer $PAT" | jq
```


#### Introspection Endpoint

Now, playing the Gateway role, we are going to consume the Introspection Endpoint asking the IdP to validate the Access Token. We use the [``-u`` **curl** option](https://curl.se/docs/manpage.html#-u) to specify our Client Id and Client Secret.

```
curl -s -X POST "$ISSUER_URL/introspect" \
  -d "token=$TOKEN" \
  -u "$CLIENT_ID:$CLIENT_SECRET" | jq
```


Here's a typical response. The “active” at the bottom says the plugin is still good.

```
{
  "active": true,
  "claim1": "claim1",
  "client_id": "xxxxxxxx",
  "scope": "scope1"
}
```



However, if you wait for the Access Token timeout (in our case, the defined it as 30 seconds), the Endpoint returns a different output saying so:

```
{
  "active": false
}
```
