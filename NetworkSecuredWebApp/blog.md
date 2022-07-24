
# Reference Architecture for Network Secured Azure Web App

> Cloud solution architecture of Azure hosted web application from Network Security perspective using Azure App Service, Azure SQL using Private Endpoints, Azure V-nets, Azure FDN and Azure FireWalls

Applications and its infrastructure should be secured in layers whether they are running on-prem or in the cloud. Like a fortress surrounded by different kinds of security measures. Right in the centre is the Data layer, where data resides, then the Application layer, followed by Network and Perimeter. Although, Cloud makes lots of things easy for developers and administrators but security is still some thing IT teams should pay careful attention and tighten it based on their needs.

In this post I am going to talk about Network secured Application Architecture. Application layer and Data layer security is out of scope for this post.

## Highlevel Solution Architecture


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/722dr73a4zpbxrs062i9.jpg)

#### Summary of Architecture

- Web application is accessible from Public Internet through Azure Front Door.
- We can enable WAF policies on Azure Front Door to protect the app from inbound malicious requests and apply filters to inbound traffic
- Azure Web app only allows traffic from Front door. This is done through a Private Link.
- Azure Web app has private ip enabled and Regional Vnet integration is setup with RouteAll option.
- Azure SQL is created with private ip, we need to explicitly disable the public access
- Azure Firewall is used to protect the outbound requests from the web application. (Red arrow indicates outbound)

#### Azure Resources used here
* Azure Web App
* Azure SQL
* Azure Private Link Service
* Azure Private DNS
* Azure Vnet
* Azure Front door with WAF (Alternatively Azure Application Gateway can be used)
* Azure Firewall(Alternatively we could have used NSGs but Firewall gives more control)
* Azure Route Tables

***
#### Create a V-Net
Create an Azure Virtual Network with three subnets,
* one for web Application Private Endpoint,
* another for Database Private Endpoint
* lastly Integration subnet (Used for V-net Integration)

This Integration Subnet will be used by Azure Web App for Regional VNet integration so that traffic between Web App and Database stays on the backbone and utilizes Private IP for communication. By default resources deployed in different subnets under same vnet can communicate with each other. Since Private IPs are only used for inbound access we need this vnet integration other wise App tries to connect database using its Public IP. This is clearly not what we want.
```
#create vnet
az network vnet create -g $rg -n $vnet --address-prefix 10.0.0.0/16 --subnet-name  $dbsnet --subnet-prefixes 10.0.2.0/24

# Create a apps subnet
az network vnet subnet create --address-prefix 10.0.1.0/24 --name $fesnet --resource-group $rg --vnet-name $vnet

# integration subnet
az network vnet subnet create --address-prefix 10.0.3.0/24 --name $intgnet --resource-group $rg --vnet-name $vnet

Create the Private DNS Zones for WebApp and Database

#create private dns zone
$webappdns = 'privatelink.azurewebsites.net'
    az network private-dns zone create `
    --resource-group $rg `
    --name $webappdns
#create private dns zone
$dbdns = 'privatelink.database.windows.net'
    az network private-dns zone create `
    --resource-group $rg `
    --name $dbdns
```
#### Create an Azure SQL Database with private endpoint.

Although Private IP is enabled for Azure SQL we still need to explicitly block public access to the database as, it is open by default.
```
#create azure sql server
az sql server create -g $rg -n $sqlserver -u $admin -p $password

#Create DB
az sql db create -g $rg -s $sqlserver -n orgdb -z false -e GeneralPurpose -f Gen5 -c 2

Create Private Link Service Connection between Private Endpoint and Database.

$sqlid = $(az sql server list -g $rg --query '[].[id]' --output tsv)

$epName = 'sqlpvtep'
az network private-endpoint create `
    --name $epName `
    --resource-group $rg `
    --vnet-name $vnet --subnet $dbsnet `
    --private-connection-resource-id $sqlid `
    --group-id sqlServer `
    --connection-name 'sqlpvtconn'

az network private-dns link vnet create `
    --resource-group $rg `
    --zone-name $dbdns `
    --name 'pa1pocdbdnsvnetlink' `
    --virtual-network $vnet `
    --registration-enabled true

az network private-endpoint dns-zone-group create `
   --resource-group $rg `
   --endpoint-name $epName `
   --name 'pa1pocdbzonegrp' `
   --private-dns-zone $dbdns `
   --zone-name $dbdns
```
#### Create an Linux based App service Plan and an Azure Web App

Enable Private Endpoints and deploy the given image
```
az appservice plan create -n 'pa1-poc-asp' -g $rg --is-linux --location 'Australia East' --sku P1V2 --number-of-workers 1
az webapp create --name 'pa1-poc-web' --plan 'pa1-poc-asp' -g $rg --runtime 'DOTNETCORE:6.0' --vnet $vnet --subnet $intgnet

$dockerImage = 'chintupawan/pjtalkstech:nwsecweb'
az webapp config container set --docker-custom-image-name $dockerImage --name 'pa1-poc-web' --resource-group $rg

az webapp config connection-string set --connection-string-type SQLAzure -g $rg -n 'pa1-poc-web' --settings Default='$connstr'

Create Private Link Service Connection between Private Endpoint and WebApp.

az network vnet subnet update `
--name $fesnet `
--resource-group $rg `
--vnet-name $vnet `
--disable-private-endpoint-network-policies true

$webappid = $(az webapp list -g $rg --query '[].[id]' --output tsv)

$wepName = 'webpvtep'
az network private-endpoint create `
    --name $wepName `
    --resource-group $rg `
    --vnet-name $vnet --subnet $fesnet `
    --private-connection-resource-id $webappid `
    --group-id sites `
    --connection-name 'webpvtconn'

az network private-dns link vnet create `
    --resource-group $rg `
    --zone-name $webappdns `
    --name 'pa1pocwebdnsvnetlink' `
    --virtual-network $vnet `
    --registration-enabled true

az network private-endpoint dns-zone-group create `
   --resource-group $rg `
   --endpoint-name $wepName `
   --name 'pa1pocwebzonegrp' `
   --private-dns-zone $webappdns `
   --zone-name $webappdns
```
#### Create Azure Front Door with premium SKU with WAF Policies.

Premium allows us to use Private Link Service.

Create a private link service between Azure Front Door and Azure Web App so that WebApp is only accessible from the Azure Front door.

We need to setup Azure Front door origin and route.
```
 az afd profile create `
   --profile-name pa1pocfd `
   --resource-group $rg `
   --sku Premium_AzureFrontDoor

   az afd endpoint create `
    --resource-group $rg `
    --endpoint-name pa1pocfdep `
    --profile-name pa1pocfd `
    --enabled-state Enabled

    az afd origin-group create `
    --resource-group $rg `
    --origin-group-name og `
    --profile-name pa1pocfd `
    --probe-request-type GET `
    --probe-protocol Http `
    --probe-interval-in-seconds 60 `
    --probe-path '/'`
    --sample-size 4 `
    --successful-samples-required 1 `
    --additional-latency-in-milliseconds 50 
   #https://docs.microsoft.com/en-us/azure/app-service/network-secure-outbound-traffic-azure-firewall
   #https://docs.microsoft.com/lb-LU/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app

    az afd origin create `
    --resource-group $rg `
    --host-name pa1-poc-web.azurewebsites.net `
    --profile-name pa1pocfd `
    --origin-group-name og `
    --origin-name pa1pocweb `
    --origin-host-header pa1-poc-web.azurewebsites.net `
    --priority 1 `
    --weight 1000 `
    --enabled-state Enabled `
    --http-port 80 `
    --https-port 443 `
    --enable-private-link True `
    --private-link-location AustraliaEast `
    --private-link-request-message 'From AFD' `
    --private-link-resource $webappid `
    --private-link-sub-resource sites
   # az network private-link-resource list -g $rg -n 'pa1-poc-web' --type Microsoft.Web/sites

    az afd route create `
    --resource-group $rg `
    --profile-name pa1pocfd `
    --endpoint-name pa1pocfdep `
    --forwarding-protocol MatchRequest `
    --route-name route `
    --https-redirect Enabled `
    --origin-group og `
    --supported-protocols Http Https `
    --link-to-default-domain Enabled 
```
In the above script we have created Front door, origin, route and a private link to web app. We need to approve the Private Link connection request that we created in the last part of the script

Navigate to **WebApp>Networking > Private endpoints**

![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/6dryddmch5zsqtrgfhd6.png)

Select the pending row and hit Approve.

Finally, Navigate to Azure Front Door Resource from Overview side nav you can find the End Point hosted. This is the url of you web application.


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/s3lidcb992e653qhgioo.png)

#### Create Azure Firewall, Public IP, Route Table and Application Rule
```
#create Firewall
$fwName = "pa1-poc-fw"
    az network firewall create `
    --name $fwName `
    --resource-group $rg `
    --location $loc
# create Public IP
$pip = "pa1-poc-pip"
az network public-ip create `
    --name $pip `
    --resource-group $rg `
    --location $loc `
    --allocation-method static `
    --sku standard

az network firewall ip-config create `
    --firewall-name $fwName `
    --name FW-config `
    --public-ip-address $pip `
    --resource-group $rg `
    --vnet-name $vnet

az network firewall update `
    --name $fwName `
    --resource-group $rg

az network public-ip show `
    --name $pip `
    --resource-group $rg
$fwprivaddr="$(az network firewall ip-config list -g $rg -f $fwName --query "[?name=='FW-config'].privateIpAddress" --output tsv)"

#create route table
$rt = "pocrt-table"
az network route-table create `
    --name $rt `
    --resource-group $rg `
    --location $loc `
    --disable-bgp-route-propagation true

az network route-table route create `
  --resource-group $rg `
  --name pocroute `
  --route-table-name $rt `
  --address-prefix 0.0.0.0/0 `
  --next-hop-type VirtualAppliance `
  --next-hop-ip-address $fwprivaddr

#associate route table to ovnet
  az network vnet subnet update `
  -n $intgnet `
  -g $rg `
  --vnet-name $vnet `
  --address-prefixes 10.0.3.0/24 `
  --route-table $rt
  
  #create application firewall
  az network firewall application-rule create `
  --collection-name poccoll `
  --firewall-name $fwName `
  --name AllowAPI `
  --protocols Http=80 Https=443 `
  --resource-group $rg `
  --target-fqdns api.my-ip.io `
  --source-addresses 10.0.3.0/24 `
  --priority 200 `
  --action Allow
```
NOTE: Here I am using Azure Classic Rules instead of Firewall policy, for production scenario please use policies.

#### Conclusion

This is a reference architecture, please take it with a grain of salt. Make sure you follow Azure Well Architected Framework and Azure Design Principles before implementing your solution.

#### References

* [Azure Firewall](https://docs.microsoft.com/en-us/azure/firewall/deploy-cli)
* [Secure outbound Access from Web App](https://docs.microsoft.com/en-us/azure/app-service/network-secure-outbound-traffic-azure-firewall)
* [Network Hardened WebApp](https://docs.microsoft.com/en-us/azure/architecture/example-scenario/security/hardened-web-app)
* [Azure App Service , Zero to Hero](https://azure.github.io/AppService/2020/08/14/zero_to_hero_pt6.html)