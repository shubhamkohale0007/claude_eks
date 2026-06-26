# Terraform EKS Project - Code Explanation (Hinglish)

---

## Quickstart — Kaise Chalayein

### Step 1: `.env` file banao (`.env.example` copy karo)

```bash
cp .env.example .env
```

`.env` mein sirf yeh values apne hisaab se badlo:

| Variable | Dev | Prod |
|----------|-----|------|
| `ENVIRONMENT` | `dev` | `prod` |
| `CLUSTER_NAME` | `my-eks-dev` | `my-eks-prod` |
| `PUBLIC_ACCESS_CIDRS` | `0.0.0.0/0` | `203.0.113.10/32` (apna IP) |
| `SINGLE_NAT_GATEWAY` | `true` | `false` |
| `NODE_INSTANCE_TYPE` | `m5.large` | `m5.xlarge` |

### Step 2: Make commands

```bash
make init      # Backend setup — bucket/key/region .env se automatic
make plan      # Kya banega preview mein dekhna
make apply     # Actually deploy karo

make validate  # Syntax check
make fmt       # Code format karo
make output    # Cluster details dekho
make destroy   # Sab hatao (careful!)
```

### Step 3: Pehli baar deploy karne pe (2 phases)

```bash
# Phase 1 — pehle sirf VPC + EKS cluster
make phase1

# Phase 2 — baaki sab (IRSA, nodes, addons)
make phase2
```

> **Note:** `make` Windows pe Git Bash ya Chocolatey se chahiye: `choco install make`

### Kaise kaam karta hai `.env` → Terraform

```
.env file
  CLUSTER_NAME=my-eks-dev
  AZS=us-east-1a,us-east-1b,us-east-1c
       ↓
Makefile (include .env)
  TF_VAR_cluster_name = my-eks-dev
  TF_VAR_azs          = ["us-east-1a","us-east-1b","us-east-1c"]  ← JSON array
  -backend-config="key=eks/dev/terraform.tfstate"                  ← backend bhi .env se
       ↓
terraform apply   ← koi alag environment folder nahi
```

---

## Project Ka Overall Structure

```
terraform-eks/
├── bootstrap/                    ← S3 bucket & DynamoDB (state management)
├── environments/
│   ├── dev/                      ← Development environment
│   ├── staging/                  ← Staging environment
│   └── prod/                     ← Production environment
└── modules/
    ├── vpc/                      ← Network layer
    ├── eks-cluster/              ← Kubernetes control plane
    ├── self-managed-node-group/  ← Worker machines (EC2)
    ├── irsa/                     ← IAM permissions for K8s pods
    └── addons/                   ← Extra tools (ALB, Autoscaler)
```

Yeh ek **production-grade AWS EKS (Kubernetes) cluster** hai jo Terraform se banaya gaya hai. Har cheez modular hai — matlab ek hi module ko dev, staging, aur prod mein reuse karte hain.

---

## Module-by-Module Explanation

---

### 1. VPC Module (`modules/vpc/main.tf`)

**Kya hai:** Yeh AWS ka private network banata hai jisme sara cluster rahega.

```
Internet
    |
Internet Gateway (IGW)
    |
Public Subnets  ──→  NAT Gateway (Elastic IP)
                           |
                     Private Subnets  ←── EKS Nodes yahan rehte hain
```

**Important cheezein:**
- **Public subnets** mein sirf NAT Gateway aur Load Balancers jaate hain
- **Private subnets** mein worker nodes rehte hain — internet se directly access nahi hote
- **NAT Gateway** nodes ko internet access deta hai (outbound only)
- **VPC Endpoints** banaye hain S3, ECR ke liye

#### Security Points - VPC

| Point | Code | Risk |
|-------|------|------|
| ✅ Nodes private subnets mein hain | `map_public_ip_on_launch = false` (private subnet) | Nodes internet pe expose nahi |
| ✅ VPC Endpoints hain | `aws_vpc_endpoint.s3`, `ecr_api`, `ecr_dkr` | Docker images pull karna internet se nahi hoga, AWS network ke andar se hoga |
| ⚠️ Dev mein single NAT | `single_nat_gateway = true` | Cost save hoti hai but ek AZ fail ho toh outbound traffic band — prod mein yeh change karo |

---

### 2. EKS Cluster Module (`modules/eks-cluster/main.tf`)

**Kya hai:** Yeh Kubernetes ka **Control Plane** banata hai — API server, etcd, scheduler sab AWS manage karta hai.

#### Security Points - EKS Cluster

**1. Public Access with `0.0.0.0/0` — CRITICAL ISSUE**

```hcl
# environments/dev/main.tf (line 45-46)
endpoint_public_access  = true
public_access_cidrs     = ["0.0.0.0/0"]
```

> **Kya problem hai:** Kubernetes API server duniya mein kisi ke bhi liye accessible hai. Agar credentials leak ho gayi toh koi bhi cluster access kar sakta hai.
>
> **Fix:** Apna office/VPN IP restrict karo: `["203.0.113.10/32"]`

**2. Logging enabled hai — Good**

```hcl
enabled_log_types = ["api", "audit", "authenticator"]
```

> **Kya acha hai:** Teen important logs capture ho rahi hain:
> - `api` — koi bhi API call
> - `audit` — kaun kya kar raha hai cluster mein
> - `authenticator` — login attempts

**3. IAM Role correctly scoped hai**

```hcl
Principal = { Service = "eks.amazonaws.com" }
```

> Sirf EKS service ko hi yeh role assume karne ki permission hai — koi human user nahi.

**4. CloudWatch logs 30 days retain hote hain**

```hcl
retention_in_days = 30
```

> Compliance ke liye theek hai, prod mein 90 ya 365 days consider karo.

---

### 3. Self-Managed Node Group (`modules/self-managed-node-group/main.tf`)

**Kya hai:** Yeh EC2 machines (worker nodes) banata hai jisme actual application pods run karenge.

#### Security Points - Node Group

**1. IMDSv2 Required — Excellent**

```hcl
# line 97-101
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # IMDSv2 enforce kar raha hai
  http_put_response_hop_limit = 2
}
```

> **Kyun important:** IMDSv1 mein ek simple HTTP request se EC2 metadata (aur IAM credentials) steal ho sakti thi. IMDSv2 token-based hai — SSRF attacks se protect karta hai.
>
> ✅ Yeh bilkul sahi hai.

**2. EBS Disk Encrypted hai**

```hcl
ebs {
  encrypted = true   # Disk encryption on hai
}
```

> **Acha:** Agar koi EC2 disk snapshot le bhi le toh data readable nahi hoga.

**3. SSM Access enabled hai — Good (No SSH needed)**

```hcl
policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

> **Kyun acha:** Nodes mein SSH port (22) khuli nahi hai. AWS Systems Manager se secure shell access milti hai bina SSH key ke. No bastion host needed.

**4. Node Security Group — Potential Issue**

```hcl
# line 53-60
resource "aws_security_group_rule" "node_self_ingress" {
  from_port = 0
  to_port   = 65535
  protocol  = "-1"    # All traffic between nodes
}

resource "aws_security_group_rule" "node_egress" {
  cidr_blocks = ["0.0.0.0/0"]   # Unrestricted outbound
}
```

> **Node-to-node:** Sabhi ports open hain nodes ke beech — yeh Kubernetes ke liye zaroori bhi hai, but agar ek pod compromise ho toh lateral movement easy ho sakti hai. NetworkPolicy lagao K8s mein.
>
> **Outbound:** Nodes internet pe kuch bhi bhej sakte hain — data exfiltration possible. Egress restrict karo ya AWS Network Firewall use karo.

**5. Optimal AMI — SSM Parameter se**

```hcl
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/.../recommended/image_id"
}
```

> ✅ AWS ka official, patched EKS AMI use ho raha hai — khud koi custom AMI nahi. Yeh secure practice hai.

---

### 4. IRSA Module (`modules/irsa/main.tf`)

**Kya hai:** IRSA = **IAM Roles for Service Accounts** — Kubernetes pods ko AWS permissions dene ka secure tarika.

```
Old way:  Pod → EC2 Instance Role → Full AWS Access (sab pods ko)
New way:  Pod → Service Account → IRSA Role → Sirf specific permissions
```

**Code explanation:**

```hcl
condition {
  test     = "StringEquals"
  variable = "${var.oidc_provider_url}:sub"
  values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
}
```

**Matlab:** Sirf `kube-system` namespace ka `aws-node` service account hi yeh role assume kar sakta hai. Koi dusra pod nahi.

#### Security Points - IRSA

| Point | Status |
|-------|--------|
| Double condition check (sub + aud) | ✅ Excellent — prevents confused deputy attacks |
| Specific namespace + service account | ✅ Least privilege principle |
| OIDC provider se verify hota hai | ✅ Cryptographically signed tokens |

---

### 5. Dev Environment (`environments/dev/main.tf`)

**Yeh file** sabhi modules ko ek saath wire karta hai.

**aws-auth ConfigMap:**

```hcl
resource "kubernetes_config_map_v1_data" "aws_auth" {
  data = {
    mapRoles = yamlencode([{
      rolearn  = module.node_group.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }])
  }
}
```

> **Kya hai:** Nodes ko cluster join karne ki permission deta hai. Sirf node role mapped hai — koi admin access nahi.

**Cluster Autoscaler Policy — Condition-Protected:**

```hcl
condition {
  test     = "StringEquals"
  variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
  values   = ["true"]
}
```

> ✅ Autoscaler sirf **tagged** autoscaling groups ko modify kar sakta hai — dusre AWS accounts ke ASG ko touch nahi kar sakta.

---

## Security Score Card

| Area | Status | Issue |
|------|--------|-------|
| Nodes private subnets mein | ✅ Safe | — |
| IMDSv2 enforced | ✅ Excellent | — |
| EBS encrypted | ✅ Good | — |
| No SSH, SSM use | ✅ Good | — |
| CloudWatch logging | ✅ Good | Prod mein retention badhao |
| IRSA double-condition | ✅ Excellent | — |
| VPC Endpoints | ✅ Good | — |
| **K8s API `0.0.0.0/0`** | ❌ CRITICAL | IP restrict karo |
| Node egress unrestricted | ⚠️ Medium | Outbound filter karo |
| Single NAT in dev | ⚠️ Low | Prod mein multi-NAT use karo |
| `PRESERVE` on addon update | ⚠️ Low | Customizations patch pe survive karti hain |

---

## Top 3 Priority Fixes

### Fix 1 — (Critical) API Server access restrict karo

```hcl
# environments/dev/main.tf line 45-46
public_access_cidrs = ["YOUR.OFFICE.IP/32"]   # 0.0.0.0/0 nahi
```

### Fix 2 — (Medium) Kubernetes NetworkPolicy lagao

Pods ke beech traffic control ke liye (yeh Terraform se bahar hai, K8s manifests mein karo):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### Fix 3 — (Medium) Prod mein public access band karo

```hcl
# environments/prod/main.tf
endpoint_public_access  = false
endpoint_private_access = true
```

Aur sirf VPN/bastion se access do.

---

---

## Interview Questions & Answers

---

### TERRAFORM

---

**Q1. Terraform state file kya hota hai? Isko S3 mein kyun rakhte hain?**

> State file Terraform ka "memory" hai — usme likha hota hai ki abhi AWS pe kya resources exist karte hain. Locally rakhoge toh team mein ek saath kaam karna mushkil ho jaata hai aur conflict aata hai. S3 mein rakhne se:
> - Sab team members ek hi state dekhte hain
> - DynamoDB lock lagta hai — do log ek saath `apply` nahi kar sakte
> - `encrypt = true` se state file encrypted rehti hai (usme sensitive values bhi hoti hain)

---

**Q2. `terraform init`, `plan`, `apply` mein kya fark hai?**

> - `init` — plugins download karta hai, backend setup karta hai. Ek baar karna padta hai ya backend change hone pe.
> - `plan` — sirf preview dikhata hai, kuch change nahi hota. "Kya hoga" batata hai.
> - `apply` — actually AWS pe resources banata/badalta/hatata hai.

---

**Q3. Modules kyun banate hain? Iske kya fayde hain?**

> Modules reusable code blocks hain — jaise functions programming mein. Is project mein `vpc`, `eks-cluster`, `irsa` alag modules hain jo dev/staging/prod teen jagah same code reuse karte hain. Ek jagah fix karo — teeno jagah fix ho jaata hai.

---

**Q4. `locals` aur `variables` mein kya fark hai?**

> - `variable` — bahar se value aati hai (.env, tfvars, CLI se). User control karta hai.
> - `local` — module ke andar hi calculated value hoti hai, bahar se change nahi ho sakti. Jaise `common_tags` jo environment + project name combine karta hai.

---

**Q5. `depends_on` kab use karte hain?**

> Jab Terraform khud dependency detect na kar paye. Jaise IRSA role EKS cluster ke baad banana hai — lekin Terraform ko pata nahi kyunki doono ke beech koi direct resource reference nahi hai. Isliye explicitly `depends_on = [module.eks_cluster]` likhna padta hai.

---

**Q6. Backend mein variables kyun nahi daal sakte? Is project mein kaise handle kiya?**

> Terraform backend `init` phase mein load hota hai — tab variables available hi nahi hote. Isliye seedha variable nahi daal sakte. Is project mein `Makefile` `-backend-config` flags CLI se pass karta hai `terraform init` ke time pe, aur values `.env` se aati hain.

---

**Q7. TF_VAR_ prefix kya hota hai?**

> Terraform automatically environment variables padhta hai jo `TF_VAR_` se shuru hote hain. `TF_VAR_cluster_name=my-eks` set karo toh Terraform isko `var.cluster_name` ke roop mein use karta hai — bina kisi extra file ke.

---

### EKS & KUBERNETES

---

**Q8. EKS Control Plane aur Data Plane mein kya fark hai?**

> - **Control Plane** — Kubernetes ka brain: API server, etcd (database), scheduler, controller manager. AWS manage karta hai, aapko nahi dekhna.
> - **Data Plane** — EC2 nodes jahan actual application pods run karte hain. Is project mein self-managed node group hai.

---

**Q9. Self-Managed aur Managed Node Group mein kya fark hai?**

> | | Self-Managed | Managed |
> |--|--|--|
> | Control | Poora control tumhara | AWS manage karta hai |
> | AMI | Khud choose karo | AWS automatically update karta hai |
> | Cost | Thoda sasta | Thoda mehanga |
> | Complexity | Zyada | Kam |
>
> Is project mein **self-managed** use kiya hai — zyada control chahiye tha (custom AMI, labels, taints).

---

**Q10. CoreDNS, kube-proxy, vpc-cni — yeh addons kya karte hain?**

> - **CoreDNS** — Kubernetes ka DNS server. Pod `my-service.default.svc.cluster.local` naam se dusre pods ko dhundh sakta hai.
> - **kube-proxy** — Har node pe network rules manage karta hai. Service ka traffic sahi pod tak pohonchata hai.
> - **vpc-cni** — Har pod ko real AWS VPC IP milti hai. Pod directly VPC mein hota hai, NAT nahi chahiye.

---

**Q11. aws-auth ConfigMap kya karta hai?**

> Yeh EKS ka "gatekeeper" hai — batata hai ki kaun sa AWS IAM role Kubernetes mein kaun sa user/group hai. Is project mein:
> ```
> EC2 Node IAM Role → system:nodes group → cluster join kar sakta hai
> ```
> Iske bina nodes cluster join hi nahi kar paate.

---

**Q12. Cluster Autoscaler kaise kaam karta hai?**

> Pending pods dekhta hai (jinhe schedule nahi ho pa raha kyunki resources kam hain) → AWS Auto Scaling Group ka `desired_capacity` badhata hai → naye nodes aate hain. Idle nodes pe bhi nazar rakhta hai aur unhe hata deta hai cost bachane ke liye. Is project mein autoscaler sirf **tagged** ASG ko touch kar sakta hai (`k8s.io/cluster-autoscaler/enabled = true`).

---

### IRSA & IAM

---

**Q13. IRSA kya hai? Pehle kaise karte the aur ab kya better hai?**

> **Pehle:** Sab pods ko EC2 instance role milta tha — matlab ek pod ko S3 access chahiye toh sab pods ko mil jaata tha. Ye dangerous hai.
>
> **IRSA (IAM Roles for Service Accounts):** Ab har pod ka apna specific IAM role hota hai. Pod ka Kubernetes Service Account OIDC token generate karta hai, AWS verify karta hai, aur sirf wahi specific role milta hai.
>
> ```
> Pod (aws-node) → OIDC Token → AWS STS → AmazonEKS_CNI_Policy (sirf yahi)
> Pod (app)      → koi role nahi
> ```

---

**Q14. OIDC Provider EKS mein kyun chahiye?**

> OIDC (OpenID Connect) ek standard hai identity verify karne ka. EKS apna OIDC provider create karta hai — yeh AWS ko prove karta hai ki "yeh token genuinely is EKS cluster ke is specific pod ka hai." Bina iske AWS STS ko trust nahi hoga ki token valid hai.

---

**Q15. Is IRSA module mein `aud` condition kyun lagayi hai?**

> ```hcl
> condition {
>   variable = "oidc:aud"
>   values   = ["sts.amazonaws.com"]
> }
> ```
> Yeh **confused deputy attack** se bachata hai. Agar sirf `sub` (subject) check karo toh ek aur service ka token bhi kaam kar sakta hai. `aud` (audience) ensure karta hai ki token specifically AWS STS ke liye bana hai — kisi aur ke liye nahi.

---

### VPC & NETWORKING

---

**Q16. Internet Gateway aur NAT Gateway mein kya fark hai?**

> - **Internet Gateway** — Public subnets ke liye. Dono directions mein traffic jaata hai (inbound + outbound). Load balancers yahan hote hain.
> - **NAT Gateway** — Private subnets ke liye. Sirf outbound traffic jaata hai. Nodes internet se software download kar sakte hain lekin internet unhe directly access nahi kar sakta.

---

**Q17. VPC Endpoints kyun use kiye hain? Inke bina kya hota?**

> Bina VPC Endpoints ke: Node private subnet mein hai → NAT Gateway se internet pe jaata hai → ECR/S3 se Docker image pull karta hai → waapis aata hai. Yeh slow, costly, aur internet pe data jaata hai.
>
> VPC Endpoints se: Node → AWS private network → ECR/S3. Internet hi nahi involve hota. Faster, cheaper, aur secure.

---

### SECURITY

---

**Q18. IMDSv1 aur IMDSv2 mein kya fark hai? IMDSv1 kyun dangerous tha?**

> **IMDSv1:** Koi bhi pod `http://169.254.169.254/latest/meta-data/iam/security-credentials/` pe simple GET request se EC2 ke IAM credentials chura sakta tha. SSRF (Server-Side Request Forgery) vulnerability se yeh exploit ho chuka hai real attacks mein.
>
> **IMDSv2:** Pehle PUT request se time-limited token lena padta hai, phir ussi token se metadata access karte hain. Pods ke liye `hop_limit = 2` hai — matlab container se seedha call possible hai lekin network se nahi.

---

**Q19. Least Privilege Principle kya hai? Is project mein kahan apply hua?**

> Sirf utni hi permission do jitni zaroorat hai — isse zyada nahi. Examples:
> - IRSA: vpc-cni pod ko sirf `AmazonEKS_CNI_Policy` milta hai, S3 ya kuch aur nahi
> - Cluster Autoscaler: sirf tagged ASG ko scale kar sakta hai, arbitrary resources nahi
> - Node IAM Role: `ECR ReadOnly` hai — nodes images pull kar sakte hain, push nahi

---

**Q20. Is project mein kya security improvements karne chahiye prod ke liye?**

> 1. `public_access_cidrs = ["0.0.0.0/0"]` → specific IP pe restrict karo
> 2. `endpoint_public_access = false` karo, VPN se access do
> 3. EKS secrets encryption enable karo (KMS)
> 4. Kubernetes NetworkPolicy lagao pod-to-pod traffic restrict karne ke liye
> 5. Node egress restrict karo (sirf known domains allow karo)
> 6. CloudWatch log retention 30 days → 90/365 days karo
> 7. AWS GuardDuty enable karo EKS threat detection ke liye

---

### MAKEFILE & .ENV

---

**Q21. `.env` file git mein push kyun nahi karte?**

> `.env` mein sensitive values hoti hain — AWS region, cluster names, CIDR ranges, bucket names. Yeh accidently public repo mein chali gayi toh attacker puri infrastructure ki mapping kar sakta hai. Isliye `.gitignore` mein add kiya hai. `.env.example` push karte hain template ke liye — usme koi real value nahi hoti.

---

**Q22. List variables (AZS, subnets) ko Makefile mein JSON mein kyun convert kiya?**

> Terraform `TF_VAR_` se list variables tabhi accept karta hai jab value JSON array format mein ho: `["us-east-1a","us-east-1b"]`. `.env` mein comma-separated string convenient hai likhne ke liye — Makefile ka `json_list` function automatically convert karta hai:
> ```
> AZS=us-east-1a,us-east-1b,us-east-1c
>              ↓ Makefile
> TF_VAR_azs=["us-east-1a","us-east-1b","us-east-1c"]
> ```

---

**Q23. `make phase1` aur `make phase2` kyun alag hain?**

> Yeh **circular dependency** ka solution hai. IRSA role ke liye EKS cluster ka OIDC provider chahiye. vpc-cni addon ke liye IRSA role ARN chahiye. Lekin EKS cluster bante waqt vpc-cni addon bhi chahiye. Yeh chicken-and-egg problem hai.
>
> Solution: Pehle cluster banao (phase1), phir IRSA create hoga aur phir saath mein sab wire ho jaayega (phase2).

---

*Generated: 2026-06-26*
