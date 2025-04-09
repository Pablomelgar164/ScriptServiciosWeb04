param (
    [string]$NombreBase = "03"
)

$outputFile = "ServiciosWeb$NombreBase-output.txt"
if (Test-Path $outputFile) { Remove-Item $outputFile }

# 1. Crear VPC
$vpcId = aws ec2 create-vpc --cidr-block 172.20.0.0/16 --query 'Vpc.VpcId' --output text
aws ec2 create-tags --resources $vpcId --tags Key=Name,Value=VPC$NombreBase
Add-Content $outputFile "VPC creada: ID = $vpcId"

# 2. Crear subred pública
$subnetId = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 172.20.140.0/26 --availability-zone (aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text) --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $subnetId --tags Key=Name,Value=Subnet$NombreBase
Add-Content $outputFile "Subred publica creada: ID = $subnetId"

# 3. Internet Gateway
$igwId = aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text
aws ec2 attach-internet-gateway --internet-gateway-id $igwId --vpc-id $vpcId
aws ec2 create-tags --resources $igwId --tags Key=Name,Value=IGW$NombreBase
Add-Content $outputFile "Internet Gateway creado y asociado: ID = $igwId"

# 4. Tabla de rutas
$routeTableId = aws ec2 create-route-table --vpc-id $vpcId --query 'RouteTable.RouteTableId' --output text
aws ec2 create-route --route-table-id $routeTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $igwId
aws ec2 associate-route-table --subnet-id $subnetId --route-table-id $routeTableId
aws ec2 create-tags --resources $routeTableId --tags Key=Name,Value=RT$NombreBase
Add-Content $outputFile "Tabla de rutas creada: ID = $routeTableId"

# 5. Grupo de seguridad
$sgId = aws ec2 create-security-group --group-name SG$NombreBase --description "Acceso web y remoto" --vpc-id $vpcId --query 'GroupId' --output text
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 3389 --cidr 0.0.0.0/0
Add-Content $outputFile "Grupo de seguridad creado: ID = $sgId"

# 6. Instancia Ubuntu con Nginx
$ubuntuAmi = aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" --query 'Images | sort_by(@, &CreationDate)[-1].ImageId' --output text

$userDataUbuntu = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("#!/bin/bash
apt update
apt install -y nginx
echo 'Ubuntu Web Server - $NombreBase' > /var/www/html/index.html"))

$ubuntuId = aws ec2 run-instances --image-id $ubuntuAmi --count 1 --instance-type t2.micro --key-name vockey --security-group-ids $sgId --subnet-id $subnetId --associate-public-ip-address --user-data $userDataUbuntu --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Ubuntu$NombreBase}]" --query 'Instances[0].InstanceId' --output text
Add-Content $outputFile "EC2 Ubuntu creada: ID de instancia = $ubuntuId"

$ubuntuId = aws ec2 run-instances --image-id $ubuntuAmi --count 1 --instance-type t2.micro --key-name vockey --security-group-ids $sgId --subnet-id $subnetId --associate-public-ip-address --user-data $userDataUbuntu --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Ubuntu$NombreBase}]" --query 'Instances[0].InstanceId' --output text
Add-Content $outputFile "EC2 Ubuntu creada: ID de instancia = $ubuntuId"

# 7. Instancia Windows con IIS
$windowsAmi=$(aws ec2 describe-images --owners 801119661308 --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" --query 'Images | sort_by(@, &CreationDate)[-1].ImageId' --output text)
$userDataWin = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("<powershell>
Install-WindowsFeature -name Web-Server
Add-Content 'C:\inetpub\wwwroot\index.html' '<h1>Windows Web Server - $NombreBase</h1>'
</powershell>"))

$windowsId = aws ec2 run-instances --image-id $windowsAmi --count 1 --instance-type t2.micro --key-name vockey --security-group-ids $sgId --subnet-id $subnetId --associate-public-ip-address --user-data $userDataWin --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Windows$NombreBase}]" --query 'Instances[0].InstanceId' --output text
Add-Content $outputFile "EC2 Windows creada: ID de instancia = $windowsId"

# 8. IP elástica
$eipUbuntu = aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text
aws ec2 associate-address --instance-id $ubuntuId --allocation-id $eipUbuntu
$ipUbuntu = aws ec2 describe-addresses --allocation-ids $eipUbuntu --query 'Addresses[0].PublicIp' --output text
Add-Content $outputFile "Elastic IP Ubuntu: $ipUbuntu"

$eipWindows = aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text
aws ec2 associate-address --instance-id $windowsId --allocation-id $eipWindows
$ipWindows = aws ec2 describe-addresses --allocation-ids $eipWindows --query 'Addresses[0].PublicIp' --output text
Add-Content $outputFile "Elastic IP Windows: $ipWindows"

# Mostrar resultado
Write-Host "`n------ Recursos creados ------"
Get-Content $outputFile
