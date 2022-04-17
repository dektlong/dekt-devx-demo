
# Demo of DevX with Tanzu 

This repo contains artifacts to run a demo illustrating the vision and capabilities of Tanzu for Dev, AppOps and Platform Ops

## Preperations 

- Clone the supplychain repo ```git clone https://github.com/dektlong/dekt-supplychain```

- Verify your target cluster supports up to 7 nodes creation acroos 2 clusters with the resource and permissions outlined in 
  - ```scripts/eks-handler.sh``` 
  - ```scripts/aks-handler.sh```
  - ```scripts/minikube-handler.sh```

- Rename the folder ```tap-config``` to ```.config```

- Update values in ```.config/tap-values-full.yaml```, ```.config/tap-values-build.yaml``` and ```.config/tap-values-run.yaml```

  - ```MY_DOMAIN``` needs to be enabled to add wild-card DNS record to
  - ```MY_IMAGE_REGISTRY_HOST``` and ```MY_SYSTEM_REPO``` needs to be accessible from the TAP cluster 

- Update your registry details in ```.config/dekt-path2prod.yaml``` custom supplychain 
  - Note: since this is a custom supply chain, the registry values defined in ```tap-values-full``` are NOT applied automatically

- Review ```.config/scan-policy.yaml``` and customized if need 

- Review ```.config/tekton-pipeline.yaml``` and customized if need 

- Update values ```.config/config-values.yaml```

    - Note: ```DOMAIN``` and ```DEMO_APPS_NS``` values must much the information in ```.config/tap-values-full.yaml```

- The ingress setup is based on GoDaddy DNS, if you are using a different one, please modify ```scripts/ingress-handler.sh```

- Clone the workloads repos
```
git clone https://github.com/dektlong/mood-sensors
git clone https://github.com/dektlong/mood-portal
```

- Relocate TAP images (optional to avoid dependecies on Tanzu Network uptime)
```
./builder relocate-tap-images
```

- If running local, the script assumes the TAP VSCode plugin and Tilt are installed

## Installation

- Install the demo components and follow the prompts
```
./builder.sh init [ aks , eks , tkg, minikube]
```
  - install dev cluster
    - TAP full profile
    - Custom app accelerators 
    - Default supplychain configs for apps namespace 
    - Grype scanning policy 
    - Tekton pipline run 
    - Custom ```dekt-path2prod``` supplychain 
    - RabbitMQ operator and instance
    - system ingress rule
    - cnr dev ingress rule
  - install stage cluster (not available in minikube)
    - TAP build profile
    - Default supplychain configs for apps namespace 
    - Grype scanning policy 
    - Tekton pipline run 
  - install prod cluster (not available in minikube)
    - TAP run profile
    - Default supplychain configs for apps namespace 
    - cnr run ingress rule

  Following installation the k8s contexts are renamed to ```###-idle``` (see Clusters context)

run ```./builder.sh apis``` to add the following
  - install Spring Cloud Gateway operator (via helm)
  - add brownfield APIs routes and gateways (see ```brownfield-apis```)
  - note - this is also needed for a Global Namespaces TSM demo

## Running the demo 

### Clusters context 
 - Set the kubectl context to the pre-instaled clusters
```
./builder.sh set-context [aks on, eks on, tkg on, hyrid on]

    aks: dev, stage and prod clusters on AKS
    eks: dev, stage and prod clusters on EKS
    tkg: dev, stage and prod clusters on TKG
    hybrid: dev cluster AKS, stage cluster EKS, prod cluster TKG
```
### Inner loop

- access tap gui accelerators via the ```cloud-native-devs``` tag
  - create ```mood-sensors``` workload using the web-backend accelerator 
  - create ```mood-portal```  workload using the web-function accelerator 
  - use ```devx-mood```  as the parent application in both cases

- access the api-portal and highlight how discovery of existing APIs prior to creating new ones is done

- highlight the simplicity of the ```workload.yaml```

- show the simple tap installed command (don't actually run)
  - ```tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values-full.yaml -n tap-install```

- show all the packages installed using 
```
./demo-helper.sh dev-cluster
```

- create workloads 
```
./demo-helper.sh deploy-workloads
```
- follow workloads and supply chain progress via Backstage and/or
```
./demo-helper.sh track-sensors
./demo-helper.sh track-portal
./demo-helper.sh tail-sensors-logs
./demo-helper.sh scanning-results
```

- access tap gui accelerators using the ```cloud-native-devsecops``` tag
  - create ```dekt-path2prod``` supplychain using the microservices-supplychain accelerator with ```web-backend``` workload type 
    - include testing, binding and scanning phases, leveraging the out of the box supply-chain templates
  - Explain that the ```mood-portal``` workload is using the out-of-the-box ```source-to-url``` supply chain as configured in ```tap-values-full``

- highlight the separation of concerns between supplychain (AppOps) and supplychain-templates (Platform Ops)

- show applied supply chains using 
```
./demo-helper.sh supplychains
```

- access the live url of mood-portal workload and show the call back to the mood-sensors APIs 

- register a entities in tap backstage gui
  - https://github.com/dektlong/mood-sensors/config/backstage/catalog-info.yaml
  - https://github.com/dektlong/mood-poratl/config/backstage/catalog-info.yaml
  - show system view diagram via ```devx-mood```
  - click down on ```mood-sensors``` to show application live view

- make a code change in ```mood-portal``` app to bypass the backend api calls 
```
./demo-helper behappy
```
  - show how the supplychain re-builds and deploy a new revision with a happy dog

### Outer loop
- 'promote' to Build cluster (source code)
  ```
  ./demo-helper.sh stage-cluster
  ./demo-helper.sh promote-staging
  ```
  - show supply chain progress on multi-cluster Backstage
  - Retrieve the mood-portal supplychain deliverable output on the Build cluster
  
- 'promote' to Run cluster (Deliverable) 
  ```
  ./demo-helper.sh prod-cluster
  ./demo-helper.sh promote-production
  ```
  - show that the new Deliverable is deployed on the production domain - run.dekt.io

## Cleanup

- full cleanup to delete the cluster  ```./builder.sh cleanup [aks/eks]```

- partial cleanup to remove just workloads on all tap clusters ```./demo-helper.sh reset```

### Enjoy!


# Extras

## API-grid demo addition
### Preperations
  - Update ```dekt4pets/dekt4pets-backend.yml```  to match ```tap-values-full```
  - update ```serverUrl:``` value in ```dekt4pets/gateway/dekt4pets-gatway.yml``` and ```dekt4pets/gateway/dekt4pets-gatway-dev.yml``` to match tap-values
  - Update ```host:``` value in ```brownfield-apis``` files to match ```tap-values-full```

### Installation
- ```./api-grid.sh init```
- create the ```dekt4pets-backend``` and ```dekt4pets-frontend``` images
- setup SSO and app configs 
- deploy dekt4pets-dev-gateway

### Running the demo
- deploy dekt4pets-backend ```./api-grid.sh backend```   
  - show in api-portal dekt4pets-dev item added in real time  and how the front end team can discover and re-use backend APIs  

- deploy dekt4pets-frontend  ```./api-grid.sh frontend``` 
  - show in api portal how the frontend routes are added in real time 
- deploy a production  gateway with ingress access ```./api-grid.sh dekt4pets```
  - show in api-portal a new item dekt4pets
  - highlight the separation between routes and gateway runtime 
- Note! these apps are not using tap supply chain 

### Inner loop
- Access app accelerator developer instance  on ```acc.<APPS_APPS_SUB_DOMAIN>.<DOMAIN>```
- Development curated start 
  - Select ```onlinestore-dev``` tag
  - Select the ```Backend API for online-stores``` accelerator 
  - Select different deployment options and show generated files
  - Select different API-grid options and show generated files
- ```./demo.sh backend```
- Show how build service detects git-repo changes and auto re-build backend-image (if required)
- Show how the ```dekt4pets-gateway``` micro-gateway starts quickly as just a component of your app
- Access API Hub on ```api-portal.<APPS_APPS_SUB_DOMAIN>.<DOMAIN>```
  - Show the dekt4Pets API group auto-populated with the API spec you defined
  - now the frontend team can easily discover and test the backend APIs and reuse
  - Show the other API groups ('brownfield APIs')
- ```./demo.sh frontend```
- Access Spring Boot Observer at ```http://alv.<APPS_APPS_SUB_DOMAIN>.<DOMAIN>/apps``` to show actuator information on the backend application 
- Show the new frontend APIs that where auto-populated to the API portal

### Outer loop
- DevOps curated start 
  - Select ```onlinestore-devops``` tag
  - Select the ```API Driven Microservices workflow``` accelerator 
  - Select different deployment options and show generated files
  - Select different API-grid options and show generated files
  - Show the supply chain created via ```./demo.sh describe```
- ```./demo.sh dekt4pets```
  - show how the full supplychain for taking the app to production is manifested
- This phase will also add an ingress rule to the gateway, now you can show:
  - External traffic can only routed via the micro-gateway
  - Frontend and backend microservices still cannot be accessed directly) 
  - Access the application on 
  ```
  https://dekt4pets.<APPS_SUB_DOMAIN>.<DOMAIN>
  ```
  - login and show SSO functionality 

### Brownfield APIs
- now the backend team will leverage the 'brownfield' APIs to add background check functionality on potential adopters
- access the 'datacheck' API group and test adoption-history and background-check APIs
- explain that now other development teams can know exactly how to use a verified working version of both APIs (no tickets to off platform teams)

#### Demo brownfield API use via adding a route and patching the backend app
  - In ```workloads/dekt4pets/backend/routes/dekt4pets-backend-routes.yaml``` add
  ```
     - predicates:
        - Path=/api/check-adopter
        - Method=GET
      filters:
        - RateLimit=3,60s
      tags:
        - "Pets"    
  ```
  - In ```workloads/dekt4pets/backend/src/main/.../AnimalController.java``` add
  ```
	  @GetMapping("/check-adopter")
	public String checkAdopter(Principal adopter) {

		if (adopter == null) {
			return "Error: Invalid adopter ID";
		}

		String adopterID = adopter.getName();
    
		String adoptionHistoryCheckURI = "UPDATE_FROM_API_PORTAL" + adopterID;

   		RestTemplate restTemplate = new RestTemplate();
		
		  try
		  {
   			String result = restTemplate.getForObject(adoptionHistoryCheckURI, String.class);
		  }
		  catch (Exception e) {}

  		return "<h1>Congratulations,</h1>" + 
				"<h2>Adopter " + adopterID + ", you are cleared to adopt your next best friend.</h2>";
	}

  ```
  - ```./demo.sh backend -u ```
  - show how build-service is invoking a new image build based on the git-commit-id
  - run the new check-adopter api 
  ```
  dekt4pets.<APPS_SUB_DOMAIN>.<DOMAIN>/api/check-adopter
  ```
  - you should see the 'Congratulations...' message with the same token you received following login
#### Demo brownfield API use via a Cloud Native Runtime function
  - ```./demo.sh adopter-check ```
  - call the function via curl
  ```
    curl -w'\n' -H 'Content-Type: text/plain' adopter-check.dekt-apps.SERVING_SUB_DOMAIN.dekt.io \
    -d "datacheck.tanzu.dekt.io/adoption-history/109141744605375013560"
  ```
  - example output
  ```
    Running adoption history check..

    API: datacheck.tanzu.dekt.io/adoption-history/109141744605375013560
    Result: APPROVED

    Source: revision 1 of adopter-check
  ```
  - show how the function scales to zero after no use for 60 seconds
  ``` kubectl get pods -n dekt-apps ```
  - create a new revision
  ```./demo adopter-check -u ```
  - show how a new revision recieving 20% of the traffic is created