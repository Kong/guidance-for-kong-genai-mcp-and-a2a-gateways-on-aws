# Docusign Extension App - Development Time

With the Kong API Gateway Data Plane deployed, we need to configure it exposing an application. For the Development Time, one good option is to mock the application using the [**Kong Mocking Plugin**](https://developer.konghq.com/plugins/mocking/).

With the **Mocking Plugin** we can have a much faster and easier deployment since we don't need to provide actual upstream services or applications.

<img src="../static/images/development-time.png" width="1000" height="850"/>

The **Mocking Plugin** takes an **OpenAPI** specification to mock and expose the application.

The **OpenAPI Spec** we are going to use is [here](../openapi.yml).


## Kong Mocking Plugin

The **decK** (Declarations for Kong) tool is used to configure the **Mocking Plugin**

The **Mocking Plugin** configuration takes the **OpenAPI** specification and defines a **Kong Service** and a **Kong Route**. Note the **Kong Service** is ignored since the **Mocking Plugin** is going to manage the requests. The **decK** file can be found [here](../kong_docusign_mock.yaml)


```
deck gateway reset --konnect-control-plane-name kong-aws --konnect-token $PAT -f
deck gateway sync --konnect-control-plane-name kong-aws --konnect-token $PAT kong_docusign_mock.yaml
```


## Test the Kong API Gateway Routes

Set the ``DATA_PLANE_LB`` environment variable with domain name:

```
export DATA_PLANE_LB=kong-dp.$AWS_DOMAIN
```

You can use any of these requests to tests the Routes and the Mocking Application:

```
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeNames | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeDefinitions | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/createRecord | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/patchRecord | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/searchRecords | jq
curl -s -X POST https://$DATA_PLANE_LB/api/oauth/token | jq
```

For example, the following request:
```
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeNames | jq
```

Should return this:
```
{
  "typeNames": [
    {
      "label": "CRM Contact",
      "typeName": "Contact"
    },
    {
      "label": "Sales Opportunity",
      "typeName": "Opportunity"
    }
  ]
}
```

