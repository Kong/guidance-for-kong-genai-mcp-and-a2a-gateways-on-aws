# Step 5: Kong Identity as the OAuth2 provider for machine-to-machine access

[← Step 4](4-mcp-gateway.md) · **Step 5** · [README →](README.md)

## Why this step

API keys are fine for a demo. Once agents call agents and tools across teams, you'll want short-lived, scoped tokens that you can introspect and revoke. In OAuth2 terms that's the **client credentials** grant: each agent or app has a client ID and secret, exchanges them for a token, and the gateway checks that token on every call.

You have options for the token issuer on AWS. **Amazon Cognito** is a common choice. This step uses **Kong Identity**, the OAuth2 authorization server built into Konnect, so tokens, scopes and gateway policy are managed in one place.

## What it does, in plain English

1. Creates an **authorization server** in Kong Identity with the Konnect REST API (`AuthZ_Server_1`, audience `http://kong.dev`).
2. Adds a **scope** (`scope1`) and a **custom claim** (`claim1`) that goes into tokens.
3. Creates a **client** (`client1`) that may use the client credentials grant, with a 60-second token lifetime.
4. Adds Kong's **OpenID Connect** plugin to a route, set to validate tokens by calling Kong Identity's **introspection** endpoint.
5. Plays both sides by hand: gets a token as the client, decodes it with `jwt-cli`, then introspects it as the gateway would.

> **Read this before you run anything in this step**
>
> - **Parts of this step describe a different scenario.** The section below is titled "Docusign Extension App - Production Time" and talks about a DocuSign extension app and Data IO services. The Kong Identity mechanics (auth server, scope, claim, client, token, introspection) don't depend on DocuSign and work as written. The route and decK file are specific to that scenario.
> - **The decK file isn't in this repo.** `kong_docusign_openid_mock.yaml` isn't in this repo yet, so the `deck gateway sync` command can't run from this repo alone. The REST API calls and the token/introspection exercises can.
> - **This wipes Step 3 and Step 4.** `deck gateway reset ... -f` deletes existing configuration on `kong-aws`.
> - **Two diagrams referenced below aren't in the repo yet** (`architecture2.png`, `kong_identity.png`). Their paths are listed in [images/README.md](images/README.md).

## Before you start

- `PAT` is exported (Step 2). The API calls use the Konnect **US** region (`us.api.konghq.com`).
- `jwt-cli` is installed for `jwt decode`.

---

# Docusign Extension App - Production Time

Now, let's promote the **Extension App** to Production. That means we are going to add new components to our deployments:
* Actual Data IO Services will be deployed so we can remove the **Kong Mocking Plugin**
* Configure **Kong Identity** to play the Identity Provider role and implement the **Client Credentials Grant**
* Configure the **Extension App** to integration with **Kong Identity**

Here's the new architecture

<img src="images/step5-identity/01-architecture2.png">

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

<img src="images/step5-identity/02-kong-identity-auth-server.png">






## Kong OpenId Connect Plugin

The [Kong OpenId Connect Plugin](https://developer.konghq.com/plugins/openid-connect/) is used to implement the **OAuth2 Client Credentials Grant** between the **Docusign Extension App** and **Kong API Gateway** itself. The **decK** declaration has been updated to add the plugin. The new file can be found [here](kong_docusign_openid_mock.yaml)


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

---

## Verify

1. `curl -s $ISSUER_URL/.well-known/openid-configuration | jq` returns your authorization server's OpenID configuration.
2. The client-credentials `TOKEN=$(...)` command produces a token, and `echo $TOKEN | jwt decode -` shows `"aud": ["http://kong.dev"]`, `"scope": "scope1"` and `"claim1": "claim1"`.
3. The introspection call returns `"active": true`. Once the token's lifetime has passed, the same call returns `"active": false`. (The client is created with `access_token_duration: 60`; the text below mentions both 30 and 60 seconds.)

## What you should see

<!-- TODO: add diagram: "architecture2.png" (referenced above, not yet in the repo). Shows the "production time" architecture with Kong Identity. -->
*Image pending (`images/step5-identity/01-architecture2.png`): the "new architecture" diagram, referenced above but not yet in the repo.*

<!-- TODO: capture screenshot: Konnect → Identity, authorization server "AuthZ_Server_1" showing its client "client1", scope "scope1" and claim "claim1" -->
*Screenshot pending (`images/step5-identity/02-kong-identity-auth-server.png`): the `AuthZ_Server_1` authorization server in Konnect with its client, scope and claim.*

## Common problems

- **`AUTHZ_SERVER_ID` or `SCOPE_ID` picks the wrong item.** The commands take `.data[0]`, the first item in the list. If your Konnect org already has other auth servers or scopes, that may not be the one you just created.
- **`deck gateway sync` can't find `kong_docusign_openid_mock.yaml`.** The file isn't in this repo (see the note at the top of this step).
- **Introspection returns `"active": false` right away.** The token has a 60-second lifetime. Request a new one and introspect it straight away.
- **More:** see [docs/troubleshooting.md](docs/troubleshooting.md#step-5-kong-identity).

[← Step 4](4-mcp-gateway.md) · **Step 5** · [README →](README.md)
