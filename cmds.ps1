pf connection create --file ./<name>/azure_openai.yaml --set api_key=? api_base=https://?.openai.azure.com/ --name open_ai_connection
pf flow build --source ./<name> --output dist --format docker
cd ..\dist
docker build -t <image name>:<version> .
docker run -p 127.0.0.1:81:8080 --env OPEN_AI_CONNECTION_API_KEY=? <image name>:<version>
az login
az acr login --name ?
docker tag <image name>:<version> ?.azurecr.io/<image name>:<version>
docker push ?.azurecr.io/<image name>:<version>

# go to bicep file folder location
az login
az deployment group create --resource-group ?  --template-file main.bicep --parameters containerImageName=? containerImageVersion=?