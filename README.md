
# Demo of DevX with Tanzu 

This repo contains artifacts to run a demo illustrating the vision and capabilities of Tanzu for Dev, AppOps and Platform Ops

## Preperations 

- AKS and/or EKS access configured, with cluster creation permissions to match the specs in ```scripts/eks-handler.sh``` and ```scripts/aks-handler.sh```
- Rename the folder ```config-template``` to  ```.config``` 

- Update values in the ```.config``` directory

  - ```tap-values```: assumes access to the image registry and domains defined

- Update ```workload/dekt4pets``` folder to match ```tap-values```

  - ```image:``` value in ```backend/dekt4pets-backend.yml```

  - ```serverUrl:``` value in ```gateway/dekt4pets-gatway.yml``` and ```gateway/dekt4pets-gatway-dev.yml```

- Update ```host:``` value in ```workload/brownfield-apis``` files to match ```tap-values```

- The ingress setup is based on GoDaddy DNS, if you are using a different one, please modify ```scripts/ingress-handler.sh```
