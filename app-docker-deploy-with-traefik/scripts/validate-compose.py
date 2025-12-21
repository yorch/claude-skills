#!/usr/bin/env python3
"""
Validate docker-compose.yml files for common issues.
Usage: python validate-compose.py [docker-compose.yml] [docker-compose.for-traefik.yml]
"""

import sys
import os

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)


def validate_compose_file(filepath: str) -> list[str]:
    """Validate a docker-compose file and return list of issues."""
    issues = []
    
    if not os.path.exists(filepath):
        return [f"File not found: {filepath}"]
    
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"]
    
    if not data:
        return ["File is empty"]
    
    # Check for services
    services = data.get('services', {})
    if not services:
        issues.append("No services defined")
        return issues
    
    for name, service in services.items():
        # Check for image or build
        if 'image' not in service and 'build' not in service:
            issues.append(f"Service '{name}': Missing 'image' or 'build'")
        
        # Check for restart policy
        if 'restart' not in service:
            issues.append(f"Service '{name}': Consider adding restart policy (e.g., 'unless-stopped')")
        
        # Check environment variables format
        env = service.get('environment', [])
        if isinstance(env, list):
            for item in env:
                if isinstance(item, str) and '${' in item and '?' not in item:
                    var = item.split('=')[0] if '=' in item else item
                    issues.append(f"Service '{name}': Variable {var} - consider adding error message with ${{VAR?Error message}}")
    
    return issues


def validate_traefik_labels(filepath: str) -> list[str]:
    """Validate Traefik-specific labels in compose file."""
    issues = []
    
    if not os.path.exists(filepath):
        return [f"File not found: {filepath}"]
    
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"]
    
    if not data:
        return ["File is empty"]
    
    services = data.get('services', {})
    networks = data.get('networks', {})
    
    # Check for traefik network
    if 'traefik' not in networks:
        issues.append("Missing 'traefik' external network definition")
    elif not networks.get('traefik', {}).get('external', False):
        issues.append("Network 'traefik' should be marked as external: true")
    
    for name, service in services.items():
        labels = service.get('labels', [])
        label_dict = {}
        
        # Convert labels list to dict for easier checking
        for label in labels:
            if isinstance(label, str) and '=' in label:
                key, value = label.split('=', 1)
                label_dict[key.strip("'")] = value.strip("'")
        
        # Check if service has traefik.enable=true
        if label_dict.get('traefik.enable') == 'true':
            # Check required labels
            required_patterns = [
                'traefik.docker.network',
                'traefik.http.services.',
                'traefik.http.routers.',
            ]
            
            has_service = any('traefik.http.services.' in k for k in label_dict)
            has_router = any('traefik.http.routers.' in k for k in label_dict)
            
            if not label_dict.get('traefik.docker.network'):
                issues.append(f"Service '{name}': Missing 'traefik.docker.network' label")
            
            if not has_service:
                issues.append(f"Service '{name}': Missing traefik.http.services.*.loadbalancer.server.port label")
            
            if not has_router:
                issues.append(f"Service '{name}': Missing traefik.http.routers.* labels")
            
            # Check if service is on traefik network
            svc_networks = service.get('networks', [])
            if isinstance(svc_networks, list) and 'traefik' not in svc_networks:
                issues.append(f"Service '{name}': Has traefik labels but not on 'traefik' network")
            elif isinstance(svc_networks, dict) and 'traefik' not in svc_networks:
                issues.append(f"Service '{name}': Has traefik labels but not on 'traefik' network")
    
    return issues


def main():
    files = sys.argv[1:] if len(sys.argv) > 1 else ['docker-compose.yml']
    
    all_valid = True
    
    for filepath in files:
        print(f"\n{'='*60}")
        print(f"Validating: {filepath}")
        print('='*60)
        
        # Basic validation
        issues = validate_compose_file(filepath)
        
        # Traefik-specific validation
        if 'traefik' in filepath.lower():
            issues.extend(validate_traefik_labels(filepath))
        
        if issues:
            all_valid = False
            print("\n⚠️  Issues found:")
            for issue in issues:
                print(f"   • {issue}")
        else:
            print("\n✅ No issues found")
    
    print(f"\n{'='*60}")
    if all_valid:
        print("✅ All files validated successfully")
    else:
        print("⚠️  Some issues were found - review above")
    
    sys.exit(0 if all_valid else 1)


if __name__ == '__main__':
    main()
