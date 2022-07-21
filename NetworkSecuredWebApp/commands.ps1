az account set --name "Visual Studio Enterprise – MPN"
$rg = 'pa1-poc-rg'
$vnet = 'pa1-poc-vnet'
$dbsnet = 'dbsnet'
$fesnet = 'appsnet'
$intgnet = 'intgnet'
$loc = "Australia East"
az group create --name $rg --location $loc
#az group delete --name $rg
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
#Create a vnet and db subnet
az network vnet create -g $rg -n $vnet --address-prefix 10.0.0.0/16 --subnet-name  $dbsnet --subnet-prefixes 10.0.2.0/24
# Create a apps subnet
az network vnet subnet create --address-prefix 10.0.1.0/24 --name $fesnet --resource-group $rg --vnet-name $vnet
az network vnet subnet create --address-prefix 10.0.3.0/24 --name $intgnet --resource-group $rg --vnet-name $vnet
az network vnet subnet create --address-prefix 10.0.4.0/24 --name AzureFirewallSubnet --resource-group $rg --vnet-name $vnet

#create a SQL Server
$sqlserver = 'pa1-poc-sql'
$admin = 'pa1sqladmin'
$password = 'pa1sqlP4ssw0rd'
az sql server create -g $rg -n $sqlserver -u $admin -p $password

#Create DB
az sql db create -g $rg -s $sqlserver -n orgdb -z false -e GeneralPurpose -f Gen5 -c 2

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

#TODO 
#Create DNS Zone Entry for SQL
# az network private-dns record-set cname create -n 'sql' -g $rg --zone-name $dns
# az network private-dns record-set cname set-record -g $rg -z $dns -n 'sql' -c 'pa1-poc-sql.database.windows.net'

#enabling private end point on SQL doesnt block public access. We need to explicitly disable public access

#Create a public Web App with Vnet Integration talking to SQL
az appservice plan create -n 'pa1-poc-asp' -g $rg --is-linux --location 'Australia East' --sku P1V2 --number-of-workers 1
az webapp create --name 'pa1-poc-web' --plan 'pa1-poc-asp' -g $rg --runtime 'DOTNETCORE:6.0' --vnet $vnet --subnet $intgnet

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

$dockerImage = 'chintupawan/pjtalkstech:nwsecweb_0.1'
az webapp config container set --docker-custom-image-name $dockerImage --name 'pa1-poc-web' --resource-group $rg

az webapp config connection-string set --connection-string-type SQLAzure -g $rg -n 'pa1-poc-web' --settings Default='Server=tcp:pa1-poc-sql.database.windows.net,1433;Initial Catalog=orgdb;Persist Security Info=False;User ID=pa1sqladmin;Password=pa1sqlP4ssw0rd;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'


#Azure Front Door
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
# Deployment


az network private-link-resource list `
    --resource-group $rg `
    --name pa1-poc-web `
    --type Microsoft.Web/sites

$fwName = "pa1-poc-fw"
    az network firewall create `
    --name $fwName `
    --resource-group $rg `
    --location $loc

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


  az network vnet subnet update --help `
  -n $intgnet `
  -g $rg `
  --vnet-name $vnet `
  --address-prefixes 10.0.3.0/24 `
  --route-table $rt
  
##az network private-endpoint-connection list --id $webappid --query "[].[name,?properties.provisioningState == 'Pending']"