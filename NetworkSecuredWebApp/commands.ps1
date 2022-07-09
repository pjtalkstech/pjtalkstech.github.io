az account set --name "Visual Studio Enterprise – MPN"
$rg = 'pa1-poc-rg'
$vnet = 'pa1-poc-vnet'
$dbsnet = 'dbsnet'
$fesnet = 'appsnet'

#create private dns zone
$dns = 'pa1-poc.com'
    az network private-dns zone create `
    --resource-group $rg `
    --name $dns
#Create a vnet and db subnet
az network vnet create -g $rg -n $vnet --address-prefix 10.0.0.0/16 --subnet-name  $dbsnet --subnet-prefixes 10.0.2.0/24
# Create a apps subnet
az network vnet subnet create --address-prefix 10.0.1.0/24 --name $fesnet --resource-group $rg --vnet-name $vnet

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
    --zone-name $dns `
    --name 'pa1pocdnsvnetlink' `
    --virtual-network $vnet `
    --registration-enabled true

az network private-endpoint dns-zone-group create `
   --resource-group $rg `
   --endpoint-name $epName `
   --name 'pa1poczonegrp' `
   --private-dns-zone $dns `
   --zone-name $dns

#TODO 
#Create DNS Zone Entry for SQL
az network private-dns record-set cname create -n 'sql' -g $rg --zone-name $dns
az network private-dns record-set cname set-record -g $rg -z $dns -n 'sql' -c 'pa1-poc-sql.database.windows.net'

#enabling private end point on SQL doesnt block public access. We need to explicitly disable public access

#Create a public Web App with Vnet Integration talking to SQL
az appservice plan create -n 'pa1-poc-asp' -g $rg --is-linux --location 'Australia East' --sku P1V2
az webapp create --name 'pa1-poc-web' --plan 'pa1-poc-asp' -g $rg --runtime 'DOTNETCORE:6.0' --vnet $vnet --subnet $fesnet

# Deployment
