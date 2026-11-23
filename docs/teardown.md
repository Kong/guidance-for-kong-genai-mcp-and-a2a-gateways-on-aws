# Tear everything down

Back to the [README](../README.md).

This page removes everything the guide creates, in an order that avoids leftovers: the AI Gateway first (which also deletes its load balancer), then Kong Identity, the Kong Operator, AgentCore, the EKS cluster, the certificate and finally IAM. The EKS cluster and the AgentCore runtime are the main ongoing costs, so if you only have a few minutes, do sections 1 to 5.

> **Run once, in November 2026.** The fixes from that run are included. Run the sections in order, read each block before running it, and check its output before moving on.
>
> **Every block sets what it needs**, so it works in any terminal, including a new one. The region is written out as `us-west-2`. If you used another domain than in the examples, or another suffix for IAM names, change it where the block says so.

## 1. AI Gateway, data plane, echo backend and inventory API (Steps 2, 4 and 7)

Delete the data plane first (this also deletes its NLB), then the AI Gateway. The Kong Operator removes the gateway from Konnect when its resource is deleted, together with its agent, MCP server, model, provider, auth strategy and the Step 8 rate-limit policy. Do this while the operator is still running.

```bash
kubectl -n kong delete service,deployment httpbin --ignore-not-found
kubectl delete -f code/inventory/inventory-api.yaml --ignore-not-found
kubectl delete aigatewaydataplane kong-aws-ai-dp -n kong --wait=true
kubectl delete konnectaigateway kong-aws-ai -n kong --wait=true
kubectl delete konnectapiauthconfiguration konnect-api-auth-conf -n kong
```

Check in Konnect that **AI Gateway → Gateways** no longer lists **Kong AWS AI Gateway**. If it does, delete it there.

Delete the `ai-dp` DNS record. Set your domain on the first line:

```bash
export AWS_DOMAIN=<your domain>
export ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" --output text | cut -d'/' -f3)
export REC=$(aws route53 list-resource-record-sets --hosted-zone-id $ZONE --query "ResourceRecordSets[?Name=='ai-dp.$AWS_DOMAIN.' && Type=='A'] | [0]" --output json)
echo "$REC"
aws route53 change-resource-record-sets --hosted-zone-id $ZONE --change-batch "$(jq -n --argjson r "$REC" '{Changes:[{Action:"DELETE",ResourceRecordSet:$r}]}')" --query ChangeInfo.Status --output text
```

The `echo` shows the record before it's deleted. The last command prints `PENDING`, which means the deletion was accepted. If `echo` prints `null`, the record is already gone, and you can skip the last command.

Then confirm the load balancer is gone. This can take a minute or two:

```bash
aws elbv2 describe-load-balancers --region us-west-2 --query "LoadBalancers[?starts_with(LoadBalancerName, 'k8s-kong')].LoadBalancerName" --output text
```

It should print nothing. **Don't continue until it does.** Section 5 removes the controller that deletes load balancers, and a leftover NLB keeps billing after the cluster is gone. If one is still listed after a few minutes, delete it in the EC2 console (**Load Balancers**).

## 2. Kong Identity (Step 5)

List the authorization servers first, so you can see what you're deleting:

```bash
export PAT=<your Konnect personal access token>
curl -s https://us.api.konghq.com/v1/auth-servers -H "Authorization: Bearer $PAT" | jq -r '.data[] | "\(.id)  \(.name)  \(.issuer)"'
```

Delete the one you created in Step 5 (`AuthZ_Server_1`, unless you renamed it). `force=true` is needed: without it, Konnect refuses to delete an auth server that still has clients, scopes or claims, and returns `400`. With it, they're deleted together:

```bash
export AUTHZ_SERVER_ID=$(curl -s https://us.api.konghq.com/v1/auth-servers -H "Authorization: Bearer $PAT" | jq -r '.data[] | select(.name=="AuthZ_Server_1") | .id')
echo "deleting: $AUTHZ_SERVER_ID"
curl -s -o /dev/null -w "delete: %{http_code}\n" -X DELETE "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID?force=true" -H "Authorization: Bearer $PAT"
```

You want `delete: 204`. Tokens it issued stop validating.

## 3. Kong Operator (Step 2)

```bash
helm uninstall kong-operator -n kong-system
kubectl delete namespace kong kong-system --ignore-not-found
```

If `kubectl delete namespace kong` hangs for more than 2 minutes, a Kong resource still has a finalizer the operator didn't clear. Press Ctrl+C, list what's left with `kubectl api-resources --verbs=list --namespaced -o name | xargs -n1 kubectl get -n kong --ignore-not-found --show-kind`, and delete it in Konnect by hand.

## 4. AgentCore runtime (Steps 3 and 7)

Run this in the AgentCore project folder (`agentcorekong`). First empty the project, and check that it's empty:

```bash
agentcore remove all --yes
jq '{runtimes: [.runtimes[].name]}' agentcore/agentcore.json
```

**Only continue if it shows `"runtimes": []`.** If the project still lists a runtime, the next command would simply deploy it again. Then deploy the empty project, which deletes the runtime in AWS, and check:

```bash
agentcore deploy --region us-west-2 --yes
aws bedrock-agentcore-control list-agent-runtimes --region us-west-2 --query "agentRuntimes[?starts_with(agentRuntimeName, 'agentcorekong')].agentRuntimeName" --output text
aws cloudformation list-stacks --region us-west-2 --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?starts_with(StackName, 'AgentCore-agentcorekong')].StackName" --output text
```

The runtime list should print nothing. If the stack list still shows `AgentCore-agentcorekong-default`, delete it:

```bash
aws cloudformation delete-stack --region us-west-2 --stack-name AgentCore-agentcorekong-default
aws cloudformation wait stack-delete-complete --region us-west-2 --stack-name AgentCore-agentcorekong-default && echo "stack deleted"
```

Delete the Step 7 secret, which held the agent's Kong Identity client. `--force-delete-without-recovery` deletes it right away instead of after a recovery window, and can't be undone:

```bash
aws secretsmanager delete-secret --region us-west-2 --secret-id kong-aws-ai/inventory-agent --force-delete-without-recovery
```

If it says the secret can't be found, you didn't do Step 7, or it's already gone. Its IAM policy, `inventory-agent-secret-kong314`, is deleted in section 7.

Optionally, delete the runtime's log groups too. They outlive the runtime and cost only pennies a month, but they're leftovers. List them first:

```bash
aws logs describe-log-groups --region us-west-2 --log-group-name-prefix /aws/bedrock-agentcore/runtimes/agentcorekong --query 'logGroups[].logGroupName' --output text
```

Then delete each one it lists:

```bash
for g in $(aws logs describe-log-groups --region us-west-2 --log-group-name-prefix /aws/bedrock-agentcore/runtimes/agentcorekong --query 'logGroups[].logGroupName' --output text); do aws logs delete-log-group --region us-west-2 --log-group-name "$g" && echo "deleted $g"; done
```

The CDK bootstrap stack (`CDKToolkit`) was created on the first deploy if your account didn't have one. Leave it unless you know nothing else in the account uses CDK. Deleting it also requires emptying its S3 bucket first.

## 5. Load Balancer Controller and EKS cluster (Step 1)

Only once section 1 has confirmed the NLB is gone. Deleting the cluster takes about 10 to 15 minutes:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
eksctl delete cluster --name kong314 --region us-west-2 --wait
```

`eksctl` also deletes the node group, the Pod Identity add-on and associations, and the CloudFormation stacks it created, usually including the IAM roles it made for the Pod Identity associations.

## 6. Certificate and validation record (Step 1)

Set your domain on the first line:

```bash
export AWS_DOMAIN=<your domain>
export ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" --output text | cut -d'/' -f3)
export CERT=$(aws acm list-certificates --region us-west-2 --query "CertificateSummaryList[?DomainName=='*.$AWS_DOMAIN'].CertificateArn | [0]" --output text)
export VNAME=$(aws acm describe-certificate --certificate-arn $CERT --region us-west-2 --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text)
export VREC=$(aws route53 list-resource-record-sets --hosted-zone-id $ZONE --query "ResourceRecordSets[?Name=='$VNAME' && Type=='CNAME'] | [0]" --output json)
echo "zone=$ZONE"; echo "cert=$CERT"; echo "record=$VNAME"
```

All three lines should show values. Then delete the certificate and its validation record:

```bash
aws acm delete-certificate --certificate-arn $CERT --region us-west-2 && echo "certificate deleted"
aws route53 change-resource-record-sets --hosted-zone-id $ZONE --change-batch "$(jq -n --argjson r "$VREC" '{Changes:[{Action:"DELETE",ResourceRecordSet:$r}]}')" --query ChangeInfo.Status --output text
```

If `delete-certificate` says the certificate is in use, a load balancer still references it. Go back to section 1.

## 7. IAM roles and policies (Steps 1 and 2)

This deletes every role and customer-managed policy whose name contains your suffix, roles first. It prints each name as it goes. Set the suffix you used on the first line, for example `kong314`. Don't use a suffix that other people's IAM names might contain.

```bash
export SUFFIX=kong314
for r in $(aws iam list-roles --query "Roles[?contains(RoleName, '$SUFFIX')].RoleName" --output text); do
  echo "role: $r"
  for a in $(aws iam list-attached-role-policies --role-name $r --query 'AttachedPolicies[].PolicyArn' --output text); do aws iam detach-role-policy --role-name $r --policy-arn $a; done
  aws iam delete-role --role-name $r && echo "  deleted"
done
for p in $(aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, '$SUFFIX')].Arn" --output text); do
  echo "policy: $p"
  aws iam delete-policy --policy-arn $p && echo "  deleted"
done
```

If nothing prints under "role", `eksctl` already removed the roles in section 5. A policy that's still attached to something won't delete, which protects anything else using it.

> **No suffix?** If you kept the guide's names, delete them one by one instead: the roles `AWSLoadBalancerControllerIAMRole-kong314` and `kaigateway-aws-podid-role`, then the policies `AWSLoadBalancerControllerIAMPolicy-kong314`, `bedrock-policy-kong314` and `inventory-agent-secret-kong314` (Step 7). In a shared account, only delete names you created. Don't delete an unsuffixed `AWSLoadBalancerControllerIAMPolicy`: it existed before this guide and belongs to someone else.

## 8. Domain and hosted zone (optional)

Skip this if you used a domain you're keeping. A hosted zone costs a small monthly fee while it exists, and a domain registered in Step 1 renews automatically. Set your domain on the first line:

```bash
export AWS_DOMAIN=<your domain>
export ZONE=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" --output text | cut -d'/' -f3)
aws route53 list-resource-record-sets --hosted-zone-id $ZONE --query "ResourceRecordSets[?Type!='NS' && Type!='SOA'].[Name,Type]" --output text
```

That must print nothing: a hosted zone can't be deleted while it still has records other than `NS` and `SOA`. Then:

```bash
aws route53 delete-hosted-zone --id $ZONE
aws route53domains disable-domain-auto-renew --domain-name $AWS_DOMAIN --region us-east-1
```

Without the zone, the domain stops resolving.

## 9. Credentials and local files

- **Konnect personal access token:** revoke it in Konnect (your initials → **Personal Access Tokens**), unless you'll use it again soon. It may also be in a kongctl profile (`~/.config/kongctl/config.yaml`).
- **Working folders:** the AgentCore project (`agentcorekong`) and `mcp-headers.txt` from the steps. None of them hold secrets: the Step 7 agent's client secret is in Secrets Manager, and `agentcore.json` only holds the secret's ARN. You can delete them.

  ```bash
  rm -rf agentcorekong mcp-headers.txt
  ```

  Run it from the root of this repo.

## Check that nothing is still running

```bash
eksctl get cluster --region us-west-2
aws elbv2 describe-load-balancers --region us-west-2 --query 'LoadBalancers[].LoadBalancerName' --output text
aws bedrock-agentcore-control list-agent-runtimes --region us-west-2 --query 'agentRuntimes[].agentRuntimeName' --output text
```

None of these should list anything from this guide (`No clusters found` is good). In a shared account, other people's load balancers may still be listed. Check the **Billing** console a day later as well.
