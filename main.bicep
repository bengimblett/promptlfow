param containerImageName string
param containerImageVersion string
param tenantId string 

param aoaiName string ='begimoai'
param uamiName string = 'mychatcappumsi'
param laName string='workspacebegimpromptflow'
param kvName string = 'promptflow-kv'
param acrName string ='begimpflowacr'
param cappsenvName string ='begim-cappsenv1'
param containerappName string ='pfmychat'
//
param location string = resourceGroup().location

param secretName string = 'azoaikey'

var kvSecretsuserRole = resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

var acrPullRole = resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// ref existing service for now
resource azopenai 'Microsoft.CognitiveServices/accounts@2022-03-01' existing=  {
  name: aoaiName
}

// TODO need Az OAPI deployment

resource userAssignManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
}


resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: laName
  location: location
  properties: {
    sku: {
      name: 'standalone'
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions:true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    retentionInDays: 30
  }
}

resource kv 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: kvName
  location: location
  properties: {
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: true
  }
}


resource secret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: kv
  name: secretName
  properties: {
    value:  azopenai.listKeys().key1 

  }
}

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id,userAssignManagedIdentity.id,kv.id)
  scope: kv
  properties: {
    roleDefinitionId:  kvSecretsuserRole
    principalId: userAssignManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userAssignManagedIdentity.id, acr.id)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRole
    principalId: userAssignManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

  
  resource containerAppEnv 'Microsoft.App/managedEnvironments@2022-11-01-preview' = {
    name: cappsenvName
    location: location
    properties: {
      appLogsConfiguration: {
        destination: 'log-analytics'
        logAnalyticsConfiguration: {
          customerId:  logAnalyticsWorkspace.properties.customerId
          sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
        }
      }
      zoneRedundant: false
      workloadProfiles: [
        {
          name: 'consumption'
          workloadProfileType: 'consumption'
        }
      ]
    }
  }


  resource containerApp 'Microsoft.App/containerApps@2023-05-02-preview' = {
    name: containerappName
    location: location
    identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${userAssignManagedIdentity.id}': {}
      }
    }
    properties:{
      managedEnvironmentId: containerAppEnv.id
      configuration: {
        ingress: {
          targetPort: 8080
          external: true
        }
        secrets: [
          {
            name : secretName
            keyVaultUrl: 'https://${kvName}.vault.azure.net/secrets/${secretName}'
            identity: userAssignManagedIdentity.id
         }
        ]
        registries: [
          {
            server: '${acrName}.azurecr.io'
            identity: userAssignManagedIdentity.id
          }
        ]
      }
      template: {
        containers: [
          {
            image: '${acrName}.azurecr.io/${containerImageName}:${containerImageVersion}'
            name: containerImageName
            env: [
              {
                name: 'AZURE_OPEN_AI_CONNECTION_API_KEY'
                secretRef: secretName
              }
            ]
          }
        ]
      }
    }
    dependsOn: [
      kvRoleAssignment
      acrRoleAssignment
    ]
  }
