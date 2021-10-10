package com.example.hello;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.client.RestTemplate;
import java.util.concurrent.TimeUnit;

import java.util.function.Function;

@SpringBootApplication
public class AdopterCheckFunction {

    @Value("${TARGET:from-function}")
    String target;

    public static void main(String[] args) {
        SpringApplication.run(AdopterCheckFunction.class, args);
    }

    @Bean
    public Function<String, String> hello() {
        return (in) -> {
            
            RestTemplate restTemplate = new RestTemplate();

            String output = "\n\n*** Welcome to " + target + " ***\n";

            String adoptionHistoryAPI = "datacheck.tanzu.dekt.io/api/adoption-history?adopterID=" + in;

            String criminalRecordAPI = "datacheck.tanzu.dekt.io/api/criminal-record/" + in;

   		    output = output + "\n\n==> Running adoption history check using API: " + adoptionHistoryAPI + " ...";   
            try
		    {
   			    String adoptionHistoryResults = restTemplate.getForObject(adoptionHistoryAPI, String.class);
                TimeUnit.SECONDS.sleep(2);
		    }
		    catch (Exception e) {/*check failure*/}

            output = output + "\n\n==> Running criminal record check using API: " + criminalRecordAPI + " ...";   
            try
		    {
                String criminalRecordResults = restTemplate.getForObject(criminalRecordAPI, String.class);
                TimeUnit.SECONDS.sleep(3);
		    }
		    catch (Exception e) {/*check failure*/}
            

            output = output + "\n\nCongratulations!! Candidate " + in + " is clear to adopt their next best friend.\n";
            
            return output;
        };
    }
}
