### Prereqs

1. Create namespace
2. Adjust Pod Security (likely there is a more minmal way of doing so) `kubectl label ns observability pod-security.kubernetes.io/enforce=privileged`