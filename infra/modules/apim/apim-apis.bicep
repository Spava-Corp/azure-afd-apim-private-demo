@description('Name of the existing APIM service')
param apimName string

@description('Base backend URL reachable from APIM, without the port (for example http://10.1.4.10)')
param backendUrl string

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimName
}

resource unlimitedProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' existing = {
  parent: apimService
  name: 'unlimited'
}

var petstoreApiName = 'petstore'
var podinfoApiName = 'podinfo'
var wildcardMethods = [
  'GET'
  'POST'
  'PUT'
  'DELETE'
]

resource petstoreApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: petstoreApiName
  properties: {
    displayName: 'Petstore'
    path: 'petstore'
    protocols: [
      'https'
    ]
    serviceUrl: '${backendUrl}:8080'
  }
}

resource podinfoApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: podinfoApiName
  properties: {
    displayName: 'Podinfo'
    path: 'podinfo'
    protocols: [
      'https'
    ]
    serviceUrl: '${backendUrl}:9898'
  }
}

resource petstoreOperations 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = [for method in wildcardMethods: {
  parent: petstoreApi
  name: toLower(method)
  properties: {
    displayName: 'Forward ${method} requests'
    method: method
    urlTemplate: '/{*path}'
    templateParameters: [
      {
        name: 'path'
        required: false
        type: 'string'
      }
    ]
    responses: []
  }
}]

resource podinfoOperations 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = [for method in wildcardMethods: {
  parent: podinfoApi
  name: toLower(method)
  properties: {
    displayName: 'Forward ${method} requests'
    method: method
    urlTemplate: '/{*path}'
    templateParameters: [
      {
        name: 'path'
        required: false
        type: 'string'
      }
    ]
    responses: []
  }
}]

resource petstoreUnlimitedProduct 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  parent: unlimitedProduct
  name: petstoreApi.name
}

resource podinfoUnlimitedProduct 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  parent: unlimitedProduct
  name: podinfoApi.name
}
