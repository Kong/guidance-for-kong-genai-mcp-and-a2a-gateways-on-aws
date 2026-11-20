# Step 1: Build the AWS foundation (EKS, load balancing, domain and TLS)

[← README](README.md) · **Step 1** · [Step 2 →](2-kong-konnect-data-plane.md)

## Why this step

Kong's gateway has to run somewhere, and in this guide that place is your own AWS account. Running it on Amazon EKS means every AI request stays inside infrastructure you control, IAM governs it, and your existing AWS tooling can see it. Kong doesn't get its own island.

This step builds only AWS resources. Nothing Kong-specific exists yet.

## What it does, in plain English

| You create | What it is for |
|---|---|
| An **EKS cluster** (`kong314`, one `c5.xlarge` node, `us-west-2`) | The Kubernetes environment where Kong's data plane will run in Step 2. |
| The **EKS Pod Identity agent** add-on | Lets individual pods get IAM permissions without long-lived access keys. Kong uses this in Step 2 to call Bedrock, AgentCore and Secrets Manager. |
| The **AWS Load Balancer Controller** | Watches Kubernetes for services that ask for a load balancer and creates a real AWS NLB for them. |
| A **domain registered in Route 53** | Gives the gateway a stable public name. Optional if you already have a domain in Route 53. |
| A **wildcard ACM certificate**, validated through DNS | Lets the NLB terminate HTTPS, so traffic to Kong is encrypted using a certificate AWS manages and renews. |

## Before you start

- AWS CLI configured for an account where you can create EKS clusters, IAM policies **and roles**, Route 53 domains and ACM certificates. A role without IAM write access (some "PowerUser" roles) fails at the first `create-policy`.
- Sign in to the AWS CLI (`aws login`, or `aws sso login` for IAM Identity Center) and confirm it works with `aws sts get-caller-identity`. The `Account` it prints is the value for `<YOUR_AWS_ACCOUNT_ID>`. Sessions expire, so if a command fails with "login session has expired", sign in again.
- `eksctl`, `kubectl`, `helm`, `jq` and `curl` installed (see the [Prerequisites](README.md#prerequisites) table).
- Your AWS account ID, which you'll need in place of `<YOUR_AWS_ACCOUNT_ID>`.
- Optional: `export AWS_PAGER=""`, so AWS CLI output prints straight to the terminal instead of opening a pager.

> **Read before you copy.** The commands below use the names `kong314`, `us-west-2` and `kong-aws-ai-guidance.com` as written. If you change any of them, change them in every later command too.
>
> **Shared AWS account?** IAM policy names are global to the account. Many accounts already have an `AWSLoadBalancerControllerIAMPolicy`, possibly an outdated version, so this guide names its policy `AWSLoadBalancerControllerIAMPolicy-kong314`. If `create-policy` still fails with `EntityAlreadyExists`, use a different suffix, and use the same name in the `--permission-policy-arns` value and in [Clean up](README.md#clean-up).

---

# AWS and EKS

## EKS Cluster Creation

Create the **EKS Cluster** with:
```
eksctl create cluster --name kong314 --version 1.35 --region us-west-2 --nodegroup-name kong-node --node-type c5.xlarge --nodes 1
```

Please check all [AWS Instances Types available](https://aws.amazon.com/ec2/instance-types/). Also, check the command accordingly if you want to create your cluster in a different region or name it differently.

#### Pod Identity

The **EKS Pod Identity AddOn** allows the **AWS Load Balancer Controller** to provision new Load Balancers

```
eksctl create addon --cluster kong314 \
  --region us-west-2 \
  --name eks-pod-identity-agent
```

## AWS Load Balancer Controller

Install the **AWS Load Balancer Controller** to expose the **Kong AI Gateway Data Plane** with an **AWS NLB (Network Load Balancer)** instance. To learn mode about the **AWS Load Balancer Controller** read its [documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/)

#### Create the IAM Policy for the Controller

```
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/docs/install/iam_policy.json
```

```
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy-kong314 \
    --policy-document file://iam_policy.json
```

#### Install AWS Load Balancer Controller

Use your AWS account to create the **Pod Identity** association and install the **Load Balancer Controller**. First add the AWS EKS Helm chart repository:

```
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
```

```
eksctl create podidentityassociation \
    --cluster kong314 \
    --region us-west-2 \
    --namespace kube-system \
    --service-account-name aws-load-balancer-controller \
    --role-name AWSLoadBalancerControllerIAMRole-kong314 \
    --permission-policy-arns arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy-kong314
```

```
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName=kong314 \
  --set region=us-west-2 \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```

> **Checkpoint.** At this point the cluster exists and the Load Balancer Controller is installed in `kube-system`. Check with `kubectl -n kube-system get deployment aws-load-balancer-controller`, or with `k9s` (see Prerequisites): open the `kube-system` namespace and look for `aws-load-balancer-controller` pods in the Running state.

## Amazon Route53 Public Domain

The AI Agents will consume **Kong AI Gateway**, over a public AWS NLB (Network Load Balancer), using HTTP/S. The instructions below describe how to prepare your AWS environment to expose the NLB in a Public Domain.

Make sure you have a Registered Domain, so we can issue a Digital Certificate to be used by the NLB. If you don't have one you can follow the instructions presented in this section.

### Using a domain you already have

If you already have a domain with a **public** hosted zone in Route 53, skip the registration commands below: set `AWS_DOMAIN` to it and continue at [AWS Certificate Manager](#aws-certificate-manager).

To find which domains your account already has, list its public hosted zones and the domains registered through Route 53:

```
# Public hosted zones (this is what the ACM certificate needs)
aws route53 list-hosted-zones \
  --query "HostedZones[?Config.PrivateZone==\`false\`].[Name,Id]" --output table

# Domains registered through Route 53 (this API only works in us-east-1)
aws route53domains list-domains --region us-east-1 \
  --query "Domains[].[DomainName,Expiry]" --output table
```

Pick a domain from the first list, without the trailing dot, and skip any whose expiry date has passed. A domain that appears only in the first list is registered somewhere else, which is fine as long as the check below passes. If the first list is empty, go to [Registering a new domain](#registering-a-new-domain).

Then check that the internet actually reaches that zone, because ACM validation silently waits forever otherwise:

```
export AWS_DOMAIN=<your domain>
dig NS $AWS_DOMAIN @8.8.8.8 +short
aws route53 get-hosted-zone --id $(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" --output text | cut -d'/' -f3) \
  --query "DelegationSet.NameServers" --output text
```

Both commands must list the same name servers. If `dig` returns nothing (`NXDOMAIN`), or different name servers, the domain isn't delegated to that zone (for example, an expired registration or a zone left over from an old setup). Fix the delegation at the registrar, or pick another domain.

### Registering a new domain

Set the environment variable with the Domain to be register
```
export AWS_DOMAIN=kong-aws-ai-guidance.com
```

**AWS Route 53** acts as the Registrar. Register the Domain with the following command which is responsible for:
* Register the domain with a registrar
* Create a hosted zone automatically
* Set the NS records: the auto-created hosted zone's NS records are automatically set as the authoritative nameservers at the registrar level. This is the key part that makes the domain publicly resolvable.
* Add SOA and NS records to the hosted zone: The hosted zone starts with just those two default record sets.

Update ``contact`` parameters accordingly. **Amazon Route53** is a global service, however its API is avaiable in ``us-east-1`` region only.

```
aws route53domains register-domain \
  --domain-name $AWS_DOMAIN \
  --duration-in-years 1 \
  --auto-renew \
  --admin-contact 'FirstName=<FIRST NAME>,LastName=<LAST NAME>,ContactType=PERSON,OrganizationName=<ORG NAME>,AddressLine1=<ADDRESS>,City=<CITY>,State=<STATE>,CountryCode=<COUNTRY CODE>,ZipCode=<ZIP CODE>,PhoneNumber=<PHONE NUMBER>,Email=<EMAIL>' \
  --registrant-contact 'FirstName=<FIRST NAME>,LastName=<LAST NAME>,ContactType=PERSON,OrganizationName=<ORG NAME>,AddressLine1=<ADDRESS>,City=<CITY>,State=<STATE>,CountryCode=<COUNTRY CODE>,ZipCode=<ZIP CODE>,PhoneNumber=<PHONE NUMBER>,Email=<EMAIL>' \
  --tech-contact 'FirstName=<FIRST NAME>,LastName=<LAST NAME>,ContactType=PERSON,OrganizationName=<ORG NAME>,AddressLine1=<ADDRESS>,City=<CITY>,State=<STATE>,CountryCode=<COUNTRY CODE>,ZipCode=<ZIP CODE>,PhoneNumber=<PHONE NUMBER>,Email=<EMAIL>' \
  --privacy-protect-admin-contact \
  --privacy-protect-registrant-contact \
  --privacy-protect-tech-contact \
  --region us-east-1
```

Check the Domain Registration status. Wait until it's been successfully registered.

```
export OPERATION_ID=$(aws route53domains list-operations \
  --region us-east-1 \
  --query "Operations[?DomainName=='$AWS_DOMAIN'].{ID:OperationId,Type:Type,Status:Status}" | jq -r '.[0].ID')
```
```
aws route53domains get-operation-detail \
  --operation-id $OPERATION_ID \
  --region us-east-1 | jq -r '.Status'
```

## AWS Certificate Manager

Issue a Digital Certificate for the Domain with **AWS Certificate Manager (ACM)**. The Digital Certificate will be used during the Kong AI Gateway Data Plane deployment time. It will be attached to the NLB provisioned alongside the Data Plane deployment.

```
export CERTIFICATE_ARN=$(aws acm request-certificate \
  --domain-name "*.${AWS_DOMAIN}" \
  --validation-method DNS \
  --region us-west-2 \
  --query CertificateArn --output text)
echo $CERTIFICATE_ARN
```

This keeps the ARN of the certificate you just requested. Looking it up later by domain name returns several ARNs if an older request for the same name exists.

#### Update the Route 53 Domain

You need to update the Route 53 domain with the CNAME Record Name and Record Value that AWS ACM generated for DNS validation of your certificate. ACM can take a few seconds to generate them, so if the next commands print empty values, wait and re-run them.

Get both CNAME Record Name and Record Value:
```
export RESOURCE_RECORD_NAME=$(aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query "Certificate.DomainValidationOptions" \
  --region us-west-2 | jq -r '.[].ResourceRecord.Name')
```

```
export RESOURCE_RECORD_VALUE=$(aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query "Certificate.DomainValidationOptions" \
  --region us-west-2 | jq -r '.[].ResourceRecord.Value')
```

Get the Hosted Zone Id:
```
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" | jq -r '.[]' | cut -d'/' -f3)
```

Update the Route 53 Domain
```
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'"$RESOURCE_RECORD_NAME"'",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'"$RESOURCE_RECORD_VALUE"'"}]
      }
    }]
  }'
```

`UPSERT` creates the record, or updates it if you re-run the command.

To check that public DNS can see the record (this is what ACM checks):
```
dig +short CNAME $RESOURCE_RECORD_NAME @8.8.8.8
```

Make sure the Digital Certificate has been issued with:
```
aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN \
  --region us-west-2 --query Certificate.Status --output text
```

You should see:
```
ISSUED
```

You add the CNAME into **Route 53** because **ACM** needs proof that you control the domain. The CNAME record is a verification token, not part of your app's DNS. When you request a certificate in AWS Certificate Manager (ACM), it generates something like:

```
Name:  _abc123.<YOUR_DOMAIN>
Value: _xyz456.acm-validations.aws
Type:  CNAME
```

That's what you retrieved using the ``acm describe-certificate`` commands.

**AWS Route 53** is the DNS Authority. Adding this entry to **Route 53** allows **ACM**, acting like a DNS client and querying **Route 53** using the ``Name`` of the CNAME entry, to verify if you actually control ``<YOUR_DOMAIN>``.

---

## Verify

You're done with Step 1 when the certificate status command above prints `ISSUED`. That one check confirms the whole chain: the domain is registered, Route 53 is authoritative for it, the validation CNAME is in place, and ACM trusts it.

Keep this terminal open. Step 2 uses the `AWS_DOMAIN`, `CERTIFICATE_ARN` and `HOSTED_ZONE_ID` variables you exported here.

## Common problems

- **The certificate stays `PENDING_VALIDATION`.** ACM can't see the CNAME yet. Check that the domain registration operation has finished (the `get-operation-detail` command), that the CNAME was created in the right hosted zone, and that the domain is delegated to that zone (the `dig NS` check under [Using a domain you already have](#using-a-domain-you-already-have)). `dig +short CNAME $RESOURCE_RECORD_NAME @8.8.8.8` must return the validation value.
- **`helm install` says it can't find the `eks` repository.** Run the `helm repo add eks ...` command above first.
- **`create-policy` fails with `EntityAlreadyExists`.** The policy name is taken in this account. Use a different suffix (see the note at the top).
- **Route 53 domain commands fail in `us-west-2`.** The Route 53 Domains API is only available in `us-east-1`, which is why those commands pass `--region us-east-1`, while ACM and EKS use `us-west-2`.
- **More:** see [docs/troubleshooting.md](docs/troubleshooting.md#step-1-eks-and-networking).

[← README](README.md) · **Step 1** · [Step 2 →](2-kong-konnect-data-plane.md)
