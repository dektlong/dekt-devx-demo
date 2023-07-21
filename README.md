
# Demo of DevX with Tanzu 

This repo contains artifacts to run a demo illustrating the vision and capabilities of Tanzu for Dev, AppOps and Platform Ops

## Preparations (one time setup)

- Install the following
  - clouds CLIs for the clouds you plan to use
    - az
    - eksclt 
    - gcloud
  - tanzu CLIs with apps and services plugins
    - version 0.28.1 or above!
  - carvel (specifically imgpkg and ytt)
  - docker CLI
  - jq
  - yq
    

- Login with your cloud credentials for each cloud you plan to deploy on

- Clone the dekt-devx-demo repo ```git clone https://github.com/dektlong/dekt-devx-demo```

- Create a folder named```.config``` in the ```dekt-devx-demo``` directory

- copy ```config-templates/demo-values.yaml``` to ```.config/demo-values.yaml```

- update all values in ```.config/demo-values.yaml```

- Generate demo config yamls
```
./builder.sh generate-configs
```
- verify all yamls created successfully in the ```.config``` folder

- 
export Tanzu packages to your private registry
```
./builder.sh export-packages tap (relocates TAP and Cluster Essentials packages)

./builder.sh export-packages tbs !!requires tap registery to be installed to determine the latest TBS version

./builder.sh export-packages tds
```

```
./builder.sh export-packages scgw (if planning to use it for brownfield apis)
```

## Installation

```
./builder.sh clusters
```
  this process make take 15-20min, depends on your k8s providers of choice*

```
./builder.sh install
```

Note: you can create just the view,dev,stage clusters and install relevant demo components using ```./builder.sh devstage``` 

This scripts automated the following:

- Set k8s contexts and verify clusters created successfully
- Install demo components on ```clusters.view.name``` 
  - Carvel tools
  - TAP based on ```.config/tap-profiles/tap-view.yaml``` values
  - Custom app accelerators
  - Ingress rule to ```dns.sysSubDomain.domain``
- Install demo components on ```clusters.dev.name``` 
  - Carvel tools
  - TAP based on ```.config/tap-profiles/tap-itereate.yaml``` values
  - we use namespace-provisioner with ```dektlong/dekt-gitops/resources``` repo for the following ```ootb-testing``` supplychain resources:
    - Java apps testing pipeline 
    - Nodejs apps testing pipeline 
    - Golang apps testing pipeline 
  - Ingress rule to ```dns.devSubDomain.domain``
- Install demo components on ```clusters.stage.name``` 
  - Carvel tools
  - TAP based on ```.config/tap-profiles/tap-build.yaml``` values
  - we use namespace-provisioner with ```dektlong/dekt-gitops/resources``` repo for the following ```ootb-testing-scanning``` supplychain resources:
    - Java apps testing pipeline 
    - Nodejs apps testing pipeline 
    - Golang apps testing pipeline
    - Scan policy
    - Install CarbonBlack scanner
    - Install Snyk scanner 
- Install demo components on ```clusters.prod1.name``` and ```clusters.prod2.name``` 
  - Carvel tools
  - TAP based on ```.config/tap-profiles/tap-run1.yaml``` and ```.config/tap-profiles/tap-run1.yaml``` values
  - Ingress rules to ```dns.prod1SubDomain.domain``` and ```dns.prod2SubDomain.domain```
- Install demo components on Brownfield cluster
  - Spring Cloud Gateway operator
  - Brownfield APIs SCGW instances and routes in ```brownfield-apis``` ns
  - Add brownfield 'consumer' k8s services to TAP clusters in ```brownfield-apis``` ns
- Attach all clusters to TMC via the TMC API

   
## Running the demo 

### Inner loop

- access tap gui accelerators via the ```cloud-native-devs``` tag
  - create ```mood-sensors``` workload using the api-microservice accelerator
    - use ```devx-mood```  as the parent application
    - show service claims abstraction
  - (optional) create ```mood-portal```  workload using the web-function accelerator 
  - (optional) create ```mood-doctor```  workload using the node.js accelerator 
  

- access the api-portal and highlight how discovery of existing APIs prior to creating new ones is done
  - if planning to show Brownfield API (see below), highlight how a developer can simply access an off platform external service by calling the 'brownfield URL' directly,  e.g. ```sentiment.tanzu-sm.io/v1/check-sentiment```

- highlight the simplicity of the ```workload.yaml```

- show demo clusters TAP packages and profiles
```
./demo.sh info
```

  
- Deploy innerloop workloads
```
./demo.sh dev
```

  - Track the progress of the supply chains in the TAP gui or CLI
    ```
    ./demo.sh track dev [logs]
    ```
  - show how the RabbitMQ 'reading' single instance resource created
  - show how the Bitnami Postgres 'inventory' resource provisioned 
  - show service claims generated for both data services and mapped to the workload

- access the live url at mood-portal.```dns.devSubdomain```.```dns.domain``` and show the call back to the mood-sensors APIs and the mood-analyzer outputs in ()

- show system components ```devx-mood```
- click on ```mood-sensors``` to show application live view

### Outer loop
- 'promote' to Staging phase
```
./demo.sh stage
```
  - show workload created pointing to ```release``` branch instead of ```dev``` branch
  - show the enhanced supply chain (dekt-src-to-api-with-scan with scanning) progress on multi-cluster Backstage
  - show Deliverables created in your gitops.stage repo, but NO runtime artifacts deployed
  - Track provisioned artifacts
```
./demo.sh track stage
```
  - show how the RDS Postgres 'inventory' resource provisioned 
      - note: this will take a few minutes to provision in the RDS console
  - show service claims generated for both data services and mapped to the workload
 
- 'promote' to Run cluster (Deliverable) 
```
./demo.sh prod
```
  - show deliverables deployed to ```app-namespaces.stageProd``` without building source/scanning
  - show that the new Deliverable is deployed on the production domain - mood-portal.```dns.prodSubdomain```.```dns.domain```
  - show how the RDS Postgres 'inventory' resource provisioned 
      - note: this will take a few minutes to provision in the RDS console
 - Track provisioned data services

    ```
    ./demo.sh services prod
    ```
  - show how the RDS Postgres 'inventory' resource provisioned 
      - note: this will take a few minutes to provision in the RDS console

 
- The Secured Platform Team
  - Showcase how Tanzu helps a secured platform team role along the **4Cs of cloud native security**  (https://kubernetes.io/docs/concepts/security/overview)
  - **Code** (TAP SupplyChain: source scan, build service, pod conventions)
  - **Container** (Carbon Black: k8s runtime, app image scanning)
  - **Clusters** (TMC OPA, TSM secure connectivity)
  - **Clouds** (CSPM with SecureState , Aria Graph showing the 'devx-mood' app security guardrails) 



### Brownfield APIs (optional)

- Highlight simple developer and staging access on the TAP cluster at the ```brownfield-consumer``` namespace as if the external services are just local k8s services
- Create a Global Namespace named ```brownfield```
  - Domain: gns.```
  - Map ```brownfield-provider``` ns in ```dekt-brownfield``` cluster to ```brownfield-consumer``` ns in ```dekt-stage``` cluster
  - Skip the option to add gateway instances (they are already created), but highlight that functionality

### Create custom supply chains via Accelerators (optional)

- access tap gui accelerators using the ```cloud-native-devsecops``` tag
  - create ```dekt-src-to-api-with-scan``` supplychain using the microservices-supplychain accelerator with ```dekt-api``` workload type 
    - include testing, binding and scanning phases, leveraging the out of the box supply-chain templates
  
- highlight the separation of concerns between supplychain (AppOps) and supplychain-templates (Platform Ops)

- show applied supply chains using ```./demo.sh supplychains```

## Cleanup

- partial cleanup to remove workloads and reset configs ```./demo.sh reset```

- full cleanup to delete all clusters  ```./builder.sh delete-all```

### Enjoy!


# Extras

## API-grid demo addition
### Preparations
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
