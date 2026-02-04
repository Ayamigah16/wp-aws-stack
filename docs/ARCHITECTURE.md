# Architecture Documentation

## System Design Overview

### High-Level Architecture

This WordPress infrastructure implements a **three-tier architecture** with edge caching:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet Users                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Cloudflare CDN  │
                    │  200+ Edge PoPs  │
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
    ┌───▼───┐            ┌───▼───┐          ┌────▼────┐
    │  WAF  │            │ Cache │          │   DNS   │
    └───┬───┘            └───┬───┘          └────┬────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   AWS Region    │
                    │   (us-east-1)   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Security Group  │
                    │ - Cloudflare IPs│
                    │ - SSH (limited) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   EC2 Instance  │
                    │ Ubuntu 22.04 LTS│
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
    ┌───▼────┐          ┌────▼────┐         ┌────▼─────┐
    │ Apache │          │  MySQL  │         │ Netdata  │
    │  PHP   │          │  8.0    │         │Monitoring│
    └───┬────┘          └────┬────┘         └──────────┘
        │                    │
        └────────────────────┤
                             │
                    ┌────────▼────────┐
                    │   WordPress     │
                    │   (Latest)      │
                    └─────────────────┘
```

## Component Decisions

### 1. Compute: EC2 vs Alternatives

**Choice**: Single EC2 instance (t3.small)

**Alternatives Considered**:
- **Lightsail**: Simpler but less flexible networking, no VPC integration
- **ECS Fargate**: Higher cost, requires container expertise
- **Lambda + RDS**: Complex WordPress compatibility, cold start issues
- **EC2 Auto Scaling**: Over-engineered for single-site, adds cost

**Rationale**:
- Full control over LAMP stack configuration
- Cost-effective: ~$15/month vs ~$50+ for managed services
- Predictable performance (no cold starts)
- Direct SSH access for troubleshooting
- Industry-standard WordPress hosting pattern

**Tradeoffs**:
- Manual scaling (vs auto-scaling)
- Single point of failure (mitigated by backups + EIP)
- Requires OS-level maintenance (automated via unattended-upgrades)

### 2. Database: Embedded MySQL vs RDS

**Choice**: MySQL 8.0 on EC2 (embedded)

**Alternatives Considered**:
- **RDS MySQL**: Managed, automated backups, Multi-AZ
- **Aurora Serverless**: Auto-scaling, expensive
- **RDS Proxy**: Connection pooling, additional cost

**Rationale**:
- Cost: $0 (embedded) vs ~$15/month (RDS t3.micro)
- Simplicity: Single instance to manage
- Performance: No network latency for DB queries
- Sufficient for small-to-medium traffic sites

**When to Migrate to RDS**:
- Traffic > 10,000 daily visitors
- Need Multi-AZ high availability
- Require automated failover
- Multiple EC2 instances (horizontal scaling)

### 3. CDN: Cloudflare Free Tier

**Choice**: Cloudflare Free with DNS, CDN, WAF

**Alternatives Considered**:
- **CloudFront**: Deeper AWS integration, higher cost
- **Fastly**: More control, expensive
- **No CDN**: Direct AWS traffic, expensive data transfer

**Rationale**:
- Free tier includes:
  - Unlimited bandwidth
  - DDoS protection (unmetered)
  - Global Anycast network
  - SSL/TLS termination
  - Basic WAF rules
- 200+ edge locations (better than CloudFront Free)
- Reduces AWS data transfer costs by ~80%

**Limitations**:
- Rate limiting: 1 rule on Free tier
- WAF: Managed rulesets only (no custom rules)
- Origin pulls may be slower than CloudFront in some regions

### 4. Storage: EBS vs EFS

**Choice**: EBS gp3 30GB

**Alternatives Considered**:
- **EFS**: Shared storage for multi-instance, expensive (~$0.30/GB)
- **S3 + WordPress plugin**: Offload media, adds complexity
- **EBS gp2**: Older generation, similar cost

**Rationale**:
- Single instance doesn't need shared storage
- gp3: 3000 IOPS baseline (vs 100 IOPS for gp2 at 30GB)
- Cost: ~$2.40/month
- Encryption at rest (GDPR compliance)

**Migration Path**:
- Add S3 offload when uploads exceed 20GB
- Use EFS when scaling to multiple EC2 instances

### 5. IP Addressing: EIP vs Dynamic

**Choice**: Elastic IP (optional, default: enabled)

**Rationale**:
- Static IP for DNS A record
- Survives instance stop/start
- Free when attached to running instance
- Allows instance replacement without DNS changes

**Tradeoff**:
- $3.60/month if instance is stopped
- Can be disabled in terraform.tfvars if cost-sensitive

### 6. Monitoring: Netdata vs CloudWatch

**Choice**: Netdata (open-source, real-time)

**Alternatives Considered**:
- **CloudWatch**: Native AWS, but costs for custom metrics
- **Prometheus + Grafana**: Over-engineered, resource-intensive
- **DataDog**: Excellent but $15/host/month

**Rationale**:
- Free and open-source
- Real-time 1-second granularity
- Pre-built dashboards for Apache, MySQL, PHP
- Low overhead (~1% CPU, 100MB RAM)
- Accessible via web UI (port 19999)

**Limitation**:
- No alerting on Free tier (use CloudWatch Alarms for critical metrics)
- Single instance only (no distributed monitoring)

## Security Architecture

### Threat Model

**Assets**:
1. WordPress admin credentials
2. Database credentials
3. Customer data (if collecting)
4. Server compute resources

**Threat Actors**:
1. Automated bots (credential stuffing, vulnerability scanning)
2. Opportunistic attackers (exploiting known CVEs)
3. DDoS attackers

**Attack Vectors**:
1. Brute force on wp-login.php
2. Exploitation of outdated plugins/themes
3. SQL injection via vulnerable plugins
4. DDoS on origin server
5. SSRF via IMDS metadata service

### Defense Layers

| Layer | Control | Threat Mitigated |
|-------|---------|------------------|
| **Edge** | Cloudflare WAF | OWASP Top 10, DDoS |
| **Network** | Security Group | Unauthorized access to origin |
| **Host** | UFW + fail2ban | Brute force, port scanning |
| **Application** | WordPress hardening | File editing, plugin exploits |
| **Data** | Least privilege MySQL | SQL injection impact |
| **Identity** | SSH key-only | Weak password attacks |

### Security Controls

**Preventive**:
- Security Group: Cloudflare IPs only for HTTP/HTTPS
- SSH: Restricted to admin CIDR
- IMDSv2: Prevents SSRF attacks
- DISALLOW_FILE_EDIT: Prevents backdoor installation via admin
- MySQL: Dedicated user with minimal privileges

**Detective**:
- Fail2ban logs: `/var/log/fail2ban.log`
- Apache access logs: Failed login attempts
- Netdata: Anomalous traffic patterns

**Corrective**:
- Fail2ban: Automatic IP banning
- Unattended-upgrades: Security patches within 24h
- Backups: Daily restore point

## Network Flow

### Request Path (Cached)

```
User → Cloudflare Edge (cache HIT) → Response (0ms origin latency)
```

### Request Path (Cache MISS)

```
1. User → Cloudflare Edge (cache MISS)
2. Cloudflare → AWS Security Group (validates source IP)
3. Security Group → UFW (validates port)
4. UFW → Apache (validates Host header)
5. Apache → PHP-FPM (processes request)
6. PHP-FPM → MySQL (database query)
7. Response: MySQL → PHP → Apache → Cloudflare → User
8. Cloudflare caches response based on Cache-Control headers
```

### Cache Strategy

| Content Type | TTL | Cloudflare Behavior |
|--------------|-----|---------------------|
| Static assets (CSS, JS, images) | 30 days | Cache everything |
| HTML pages | 2 hours | Cache with revalidation |
| /wp-admin/* | 0 | Bypass cache |
| /wp-login.php | 0 | Bypass cache |
| API endpoints | 0 | Bypass cache |

## Scaling Strategy

### Vertical Scaling (Implemented)

**Current**: t3.small (2 vCPU, 2GB RAM)

**Upgrade Path**:
```
t3.small → t3.medium → t3.large → t3.xlarge
$15/mo    $30/mo      $60/mo    $120/mo
```

**When to scale**:
- CPU usage > 70% sustained
- Memory usage > 80%
- MySQL slow query log growing
- Response time > 3 seconds

### Horizontal Scaling (Not Implemented)

**Requirements**:
1. **Load Balancer**: ALB for traffic distribution
2. **Shared Database**: RDS MySQL Multi-AZ
3. **Shared Storage**: EFS or S3 for wp-content/uploads
4. **Session Management**: Redis for PHP sessions
5. **Auto Scaling Group**: 2-10 EC2 instances

**Estimated Cost**: ~$150-300/month

**When Required**:
- Traffic > 50,000 daily visitors
- Need 99.95%+ uptime SLA
- Geographic distribution required

## Disaster Recovery

### Recovery Time Objective (RTO)

**Scenario**: Complete EC2 instance failure

**Recovery Steps**:
1. Terraform destroy/apply: 5 minutes
2. Cloud-init bootstrap: 10 minutes
3. Database restore: 5 minutes
4. DNS propagation: 5 minutes
5. Validation: 5 minutes

**Total RTO**: ~30 minutes

### Recovery Point Objective (RPO)

**Daily backups**: RPO = 24 hours (acceptable for most blogs)

**Improve to 1-hour RPO**:
- Use RDS automated backups (5-minute snapshots)
- Enable MySQL binary logging
- Implement point-in-time recovery

## Cost Breakdown

### Monthly Recurring Costs

| Resource | Specification | Cost |
|----------|---------------|------|
| EC2 t3.small | 730 hours/month | $15.18 |
| EBS gp3 | 30GB | $2.40 |
| Data Transfer | ~50GB (20% of traffic) | $4.50 |
| EIP | Attached | $0.00 |
| **Total** | | **$22.08** |

### Cost Optimizations

1. **Reserved Instance**: -40% on EC2 ($9.11/month)
2. **Savings Plan**: -30% flexible commitment
3. **EBS snapshots**: Lifecycle policy for old backups
4. **Cloudflare caching**: Reduces data transfer by 80%

### Cost Scaling

| Scenario | Monthly Cost |
|----------|--------------|
| Current (t3.small) | $22 |
| High traffic (t3.medium) | $40 |
| HA setup (2x EC2 + RDS) | $150 |
| Enterprise (ASG + CloudFront) | $300+ |

## Compliance Considerations

### GDPR

- **Data Encryption**: EBS volumes encrypted at rest
- **Data Portability**: WordPress export + database dump
- **Right to Erasure**: Manual user deletion via wp-admin
- **Logging**: User IP addresses in Apache logs (consider anonymization)

### PCI-DSS

**Not PCI-compliant by default**. Required for e-commerce:
- WAF with geo-blocking
- Database field-level encryption
- Quarterly vulnerability scanning
- Annual penetration testing

**Recommendation**: Use Stripe/PayPal for payment processing (PCI compliance offloaded)

## Maintenance Windows

### Automated

- **OS patches**: Daily at 6 AM UTC (unattended-upgrades)
- **WordPress core updates**: Minor versions auto-update
- **Backups**: Daily at 2 AM UTC

### Manual (Recommended Quarterly)

- PHP version upgrade (e.g., 8.1 → 8.2)
- MySQL major version upgrade
- Review and update fail2ban rules
- Security audit and penetration testing

## Monitoring and Alerting

### Key Metrics

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU Usage | > 80% for 10 min | Scale vertically |
| Disk Usage | > 85% | Cleanup logs, expand EBS |
| MySQL Connections | > 40 | Optimize queries, consider RDS |
| Apache 5xx errors | > 10 in 5 min | Check error logs, restart Apache |
| Failed SSH attempts | > 10 in 1 hour | Review fail2ban logs |

### Future Enhancements

1. **CloudWatch Alarms**: SNS notifications for critical metrics
2. **StatusCake**: External uptime monitoring
3. **Slack Integration**: Alert notifications
4. **Prometheus Exporters**: Long-term metrics retention

---

**Document Version**: 1.0  
**Last Updated**: January 2026  
**Author**: Senior DevOps Engineer
