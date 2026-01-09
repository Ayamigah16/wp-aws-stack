#!/bin/bash
###############################################################################
# WordPress Infrastructure Validation Script
# Purpose: Comprehensive testing of deployment, security, and functionality
# Usage: ./validate.sh [EC2_IP] [DOMAIN_NAME]
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNINGS++))
}

# Parse arguments
EC2_IP="${1:-}"
DOMAIN_NAME="${2:-}"

if [ -z "$EC2_IP" ] || [ -z "$DOMAIN_NAME" ]; then
    echo "Usage: $0 EC2_IP DOMAIN_NAME"
    echo "Example: $0 203.0.113.10 example.com"
    exit 1
fi

print_header "WordPress Infrastructure Validation"
echo "Target EC2: $EC2_IP"
echo "Domain: $DOMAIN_NAME"
echo "Started: $(date)"

###############################################################################
# Test 1: DNS Resolution via Cloudflare
###############################################################################
print_header "Test 1: DNS Resolution"

DNS_RESULT=$(dig +short "$DOMAIN_NAME" @1.1.1.1 | tail -1)
if [ -n "$DNS_RESULT" ]; then
    test_pass "DNS resolves to: $DNS_RESULT"
    
    if [ "$DNS_RESULT" == "$EC2_IP" ]; then
        test_pass "DNS points to correct EC2 IP"
    else
        test_fail "DNS IP mismatch (Expected: $EC2_IP, Got: $DNS_RESULT)"
    fi
else
    test_fail "DNS resolution failed for $DOMAIN_NAME"
fi

###############################################################################
# Test 2: Cloudflare Proxy Detection
###############################################################################
print_header "Test 2: Cloudflare CDN Detection"

HEADERS=$(curl -sI "https://$DOMAIN_NAME" 2>/dev/null || echo "")

if echo "$HEADERS" | grep -qi "cf-ray"; then
    test_pass "Cloudflare proxy active (CF-Ray header present)"
else
    test_fail "Cloudflare proxy not detected"
fi

if echo "$HEADERS" | grep -qi "cf-cache-status"; then
    test_pass "Cloudflare caching header present"
else
    test_warn "CF-Cache-Status header not found"
fi

###############################################################################
# Test 3: HTTPS and SSL/TLS
###############################################################################
print_header "Test 3: HTTPS & SSL/TLS Configuration"

HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ] || [ "$HTTP_CODE" == "200" ]; then
    test_pass "HTTP accessible (status: $HTTP_CODE)"
else
    test_fail "HTTP request failed (status: $HTTP_CODE)"
fi

HTTPS_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME" 2>/dev/null || echo "000")
if [ "$HTTPS_CODE" == "200" ]; then
    test_pass "HTTPS accessible (status: 200)"
else
    test_fail "HTTPS request failed (status: $HTTPS_CODE)"
fi

# Check for redirect loops
REDIRECT_COUNT=$(curl -sL -w "%{num_redirects}" -o /dev/null "https://$DOMAIN_NAME" 2>/dev/null || echo "999")
if [ "$REDIRECT_COUNT" -lt "10" ]; then
    test_pass "No redirect loops detected ($REDIRECT_COUNT redirects)"
else
    test_fail "Possible redirect loop detected ($REDIRECT_COUNT redirects)"
fi

###############################################################################
# Test 4: Security Headers
###############################################################################
print_header "Test 4: Security Headers"

if echo "$HEADERS" | grep -qi "x-content-type-options: nosniff"; then
    test_pass "X-Content-Type-Options header present"
else
    test_warn "X-Content-Type-Options header missing"
fi

if echo "$HEADERS" | grep -qi "x-frame-options"; then
    test_pass "X-Frame-Options header present"
else
    test_warn "X-Frame-Options header missing"
fi

if echo "$HEADERS" | grep -qi "strict-transport-security"; then
    test_pass "HSTS header present"
else
    test_warn "HSTS header missing (may be set by Cloudflare)"
fi

###############################################################################
# Test 5: Direct IP Access Prevention
###############################################################################
print_header "Test 5: Origin Server Protection"

DIRECT_IP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "http://$EC2_IP" --connect-timeout 5 2>/dev/null || echo "000")
if [ "$DIRECT_IP_CODE" == "403" ] || [ "$DIRECT_IP_CODE" == "000" ]; then
    test_pass "Direct IP access blocked or unreachable (status: $DIRECT_IP_CODE)"
else
    test_fail "Direct IP access allowed (status: $DIRECT_IP_CODE) - Origin exposed!"
fi

###############################################################################
# Test 6: WordPress Specific Tests
###############################################################################
print_header "Test 6: WordPress Functionality"

WP_CONTENT=$(curl -sL "https://$DOMAIN_NAME" 2>/dev/null || echo "")

if echo "$WP_CONTENT" | grep -qi "wordpress"; then
    test_pass "WordPress detected in response"
else
    test_warn "WordPress signature not found in HTML"
fi

# Check wp-login.php
LOGIN_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/wp-login.php" 2>/dev/null || echo "000")
if [ "$LOGIN_CODE" == "200" ]; then
    test_pass "WordPress login page accessible"
else
    test_fail "WordPress login page not accessible (status: $LOGIN_CODE)"
fi

# Check wp-admin (should redirect to login)
ADMIN_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/wp-admin/" 2>/dev/null || echo "000")
if [ "$ADMIN_CODE" == "200" ] || [ "$ADMIN_CODE" == "302" ]; then
    test_pass "WordPress admin area responding"
else
    test_warn "WordPress admin area returned unexpected status: $ADMIN_CODE"
fi

###############################################################################
# Test 7: Cache Rules
###############################################################################
print_header "Test 7: Cloudflare Cache Configuration"

# Check if admin is not cached
ADMIN_CACHE=$(curl -sI "https://$DOMAIN_NAME/wp-admin/" 2>/dev/null | grep -i "cf-cache-status" || echo "")
if echo "$ADMIN_CACHE" | grep -qi "bypass\|dynamic"; then
    test_pass "wp-admin not cached (correct configuration)"
else
    test_warn "wp-admin cache status unclear: $ADMIN_CACHE"
fi

# Check if static assets are cached
STATIC_CACHE=$(curl -sI "https://$DOMAIN_NAME/wp-includes/css/dashicons.min.css" 2>/dev/null | grep -i "cf-cache-status" || echo "")
if [ -n "$STATIC_CACHE" ]; then
    test_pass "Static assets caching configured"
else
    test_warn "Static assets cache status not detected"
fi

###############################################################################
# Test 8: Rate Limiting (Login Protection)
###############################################################################
print_header "Test 8: Rate Limiting"

echo "Testing rate limiting on wp-login.php (5 requests)..."
for i in {1..5}; do
    curl -sL -o /dev/null "https://$DOMAIN_NAME/wp-login.php" 2>/dev/null
    sleep 1
done

RATE_TEST=$(curl -sI "https://$DOMAIN_NAME/wp-login.php" 2>/dev/null | head -1)
if echo "$RATE_TEST" | grep -q "200\|429"; then
    test_pass "Rate limiting endpoint responding (status: $RATE_TEST)"
else
    test_warn "Unable to verify rate limiting"
fi

###############################################################################
# Test 9: Server Health (if SSH access available)
###############################################################################
print_header "Test 9: Server Accessibility"

if nc -zw3 "$EC2_IP" 22 2>/dev/null; then
    test_pass "SSH port (22) accessible for management"
else
    test_warn "SSH port not accessible (may be restricted to specific IPs)"
fi

if nc -zw3 "$EC2_IP" 19999 2>/dev/null; then
    test_pass "Netdata port (19999) accessible"
else
    test_warn "Netdata port not accessible (may be intentionally restricted)"
fi

###############################################################################
# Test 10: Performance Check
###############################################################################
print_header "Test 10: Performance Metrics"

RESPONSE_TIME=$(curl -sL -o /dev/null -w "%{time_total}" "https://$DOMAIN_NAME" 2>/dev/null || echo "999")
if (( $(echo "$RESPONSE_TIME < 3.0" | bc -l) )); then
    test_pass "Response time acceptable: ${RESPONSE_TIME}s"
else
    test_warn "Response time high: ${RESPONSE_TIME}s"
fi

TTFB=$(curl -sL -o /dev/null -w "%{time_starttransfer}" "https://$DOMAIN_NAME" 2>/dev/null || echo "999")
if (( $(echo "$TTFB < 1.5" | bc -l) )); then
    test_pass "Time to first byte acceptable: ${TTFB}s"
else
    test_warn "Time to first byte high: ${TTFB}s"
fi

###############################################################################
# Summary
###############################################################################
print_header "Validation Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
echo "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""
echo "Completed: $(date)"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Review output above.${NC}"
    exit 1
fi
