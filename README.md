
# Demo of Tanzu API Grid ♥️😺 ♥️🐶

This repo contains artifacts to run a demo illustrating the vision and capabilities of Tanzu API Grid.

It is designed to run on any k8s.

- [Demo slides](https://docs.google.com/presentation/d/105sp3K633nnTPWn_PGxrLRb2X0atNmNN4Wlu10FgQ00/edit#slide=id.gdbf1731422_0_3)
- [Demo recording](https://bit.ly/api-grid)

## Curated Start                                                   
- Architects create patterns                                      
- Devs start quickly via curated ‘starters’                           
- API-first design boiler-plate code                                  

## Consistent Builds                                                    
- Local dev to pipeline-initiated builds                          
- Follows standard Boot tools (no docker files required)               
- Prod-optimized images, air-gapped artifacts, lifecycle support  
- GitOps for APIs - e.g. pipeline driven configuration of routes per lifecycle stage       

## Collaborative micro-APIs 
- Deploy backend service and expose its internal APIs through a dev-friendly 'app' Gateway, including simple to use SSO
- Frontend developers discover, test and reuse backend APIs via an auto-populated Hub
- Backend team add functionality leveraging 'brownfield APIs' from off-platform services 
- Publish app and configure live traffic via the gateway

## COMPLETE BEFORE STARTING !!

- Rename the folder ```config-template``` to  ```.config``` 

- Set all UPDATE_ME values in the ```.config``` directory

- Update your runtime specific values in ```workload/dekt4pets``` folder

  - ```image:``` value in ```backend/dekt4pets-backend.yml```

  - ```serverUrl:``` value in ```gateway/dekt4pets-gatway.yml``` and ```gateway/dekt4pets-gatway-dev.yml```

- Update ```host:``` value in ```workload/brownfield-apis``` files  

- The ingress setup is based on GoDaddy DNS, if you are using a different one, please modify ```scripts/update-dns.sh```

- This demo was tested well on AKS with 7 nodes of type ```Standard_DS3_v2``` (4 vCPU, 14GB memory, 28GB temp disk). If you need to change that configuration, please modify the parameters in ```platform/scripts/build-aks-cluster.sh``` function

## API Grid

### Installation
- run ```./builder.sh init-aks | init-eks ]``` to install the following:
  - TAP with the following packages
    - Clound Native Runtime
    - App Accelerator
    - App Live View
    - Build Service
    - Supply Chain components
    - Image metadata store
    - Image policy webhook
    - Scan controller
    - Grype scanner
  - Spring Cloud Gateway
  - API portal
  - Demo examples
    - App Accelerators
    - Brownfield APIs examples for API portal
    - Det4Pets backend TBS image
    - Det4Pets frontend TBS image
    - dev source-to-image supply-chain 
  

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

## Cleanup

- ```./builder.sh cleanup-aks | cleanup-eks ]```

# Enjoy!
