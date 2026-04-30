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
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
```


#### Install AWS Load Balancer Controller

Use your AWS account to create the **Pod Identity** association and install the **Load Balancer Controller**.

```
eksctl create podidentityassociation \
    --cluster kong314 \
    --region us-west-2 \
    --namespace kube-system \
    --service-account-name aws-load-balancer-controller \
    --role-name AWSLoadBalancerControllerIAMRole-kong314 \
    --permission-policy-arns arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

```
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName=kong314 \
  --set region=us-west-2 \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```



## Amazon Route53 Public Domain

The AI Agents will consume **Kong AI Gateway**, over a public AWS NLB (Network Load Balancer), using HTTP/S. The instructions below describe how to prepare your AWS environment to expose the NLB in a Public Domain.

Make sure you have a Registered Domain, so we can issue a Digital Certificate to be used by the NLB. If you don't have one you can follow the instructions presented in this section.

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
aws acm request-certificate \
  --domain-name "*.${AWS_DOMAIN}" \
  --validation-method DNS \
  --region us-west-2
```


#### Update the Route 53 Domain

You need to update the Route 53 domain with the CNAME Record Name and Record Value that AWS ACM generated for DNS validation of your certificate.

Get the Certificate ARN
```
export CERTIFICATE_ARN=$(aws acm list-certificates --region us-west-2 \
  --output json | \
  jq -r ".CertificateSummaryList[] | select(.DomainName == \"*.${AWS_DOMAIN}\") | .CertificateArn")
```


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
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "'"$RESOURCE_RECORD_NAME"'",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'"$RESOURCE_RECORD_VALUE"'"}]
      }
    }]
  }'
```


Make sure the Digital Certificate has been issued with:
```
aws acm list-certificates \
  --region us-west-2 | \
  jq -r ".CertificateSummaryList[] | select(.DomainName == \"*.${AWS_DOMAIN}\") | .Status"
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
