# https://hmcts.github.io/cloud-native-platform/troubleshooting/index.html#debug-application-startup-issues-in-aks
 # Sandbox
  az aks get-credentials --resource-group ss-sbox-00-rg --name ss-sbox-00-aks --subscription DTS-SHAREDSERVICES-SBOX --overwrite-existing
  az aks get-credentials --resource-group ss-sbox-01-rg --name ss-sbox-01-aks --subscription DTS-SHAREDSERVICES-SBOX --overwrite-existing

  # Dev
  az aks get-credentials --resource-group ss-dev-01-rg --name ss-dev-01-aks --subscription DTS-SHAREDSERVICES-DEV --overwrite-existing

  # Staging
  az aks get-credentials --resource-group ss-stg-00-rg --name ss-stg-00-aks --subscription DTS-SHAREDSERVICES-STG --overwrite-existing
  az aks get-credentials --resource-group ss-stg-01-rg --name ss-stg-01-aks --subscription DTS-SHAREDSERVICES-STG --overwrite-existing

  # Test
  az aks get-credentials --resource-group ss-test-00-rg --name ss-test-00-aks --subscription DTS-SHAREDSERVICES-TEST --overwrite-existing
  az aks get-credentials --resource-group ss-test-01-rg --name ss-test-01-aks --subscription DTS-SHAREDSERVICES-TEST --overwrite-existing

  # ITHC
  az aks get-credentials --resource-group ss-ithc-00-rg --name ss-ithc-00-aks --subscription DTS-SHAREDSERVICES-ITHC --overwrite-existing
  az aks get-credentials --resource-group ss-ithc-01-rg --name ss-ithc-01-aks --subscription DTS-SHAREDSERVICES-ITHC --overwrite-existing

  # Demo
  az aks get-credentials --resource-group ss-demo-00-rg --name ss-demo-00-aks --subscription DTS-SHAREDSERVICES-DEMO --overwrite-existing
  az aks get-credentials --resource-group ss-demo-01-rg --name ss-demo-01-aks --subscription DTS-SHAREDSERVICES-DEMO --overwrite-existing

  # Prod (Requires additional permissions)
  az aks get-credentials --resource-group ss-prod-00-rg --name ss-prod-00-aks --subscription DTS-SHAREDSERVICES-PROD --overwrite-existing
  az aks get-credentials --resource-group ss-prod-01-rg --name ss-prod-01-aks --subscription DTS-SHAREDSERVICES-PROD --overwrite-existing