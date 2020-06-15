/// Package Manager Registry API
Class ZPM.Registry Extends ZPM.REST.Base
{

Parameter VERSION = "1.0.0";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <!-- Server Info -->
  <Route Url="/" Method="GET" Call="GetInfo" Cors="true"/>
  <Route Url="/_ping" Method="GET" Call="Ping" Cors="true"/>
  
  <!-- Reset registry for debug purposes, limited access -->
  <Route Url="/_reset" Method="GET" Call="Reset" Cors="true"/>
  
  <!-- Swagger specs -->
  <Route Url="/_spec" Method="GET" Call="SwaggerSpec" Cors="true"/>
  
  <!-- All packages -->
  <Route Url="/packages/-/all" Method="GET" Call="AllPackages" Cors="true" />
  
  <!-- Package manifest -->
  <Route Url="/packages/:package/:version/manifest" Method="GET" Call="PackageManifest" Cors="true" />
  <!-- Package installer -->
  <Route Url="/packages/:package/:version/installer" Method="GET" Call="PackageInstaller" Cors="true" />
  
  <!-- Package information -->
  <Route Url="/packages/:package/?" Method="GET" Call="Package" Cors="true" />
  <!-- Package information with specified version -->
  <Route Url="/packages/:package/:version" Method="GET" Call="Package" Cors="true" />
  <!-- Publish Package -->
  <Route Url="/packages" Method="POST" Call="PublishPackage" Cors="true" />
  
  <!-- Package Archive -->
  <Route Url="/:package/-/:file" Method="GET" Call="GetArchive" Cors="true" />


  <!-- Temp url, update package, should be combined with "POST /packages"-->
  <Route Url="/package" Method="POST" Call="UpdatePackage" Cors="true" />

  
  <!-- Analytics -->
  <Route Url="/collect/:action" Method="POST" Call="CollectAnalytics" Cors="true" />

</Routes>
}

/// Package Manager general information
ClassMethod GetInfo() As %Status
{
  SET version = ..#VERSION
  If $System.CLS.IsMthd("%ZPM.PackageManager.Developer.Module", "NameOpen") {
    Set zpmModule = ##class(%ZPM.PackageManager.Developer.Module).NameOpen("zpm-registry")
    If $IsObject(zpmModule) {
      Set version = zpmModule.VersionString
    }
  }
  SET info = {
    "version": (version)
  }
  RETURN ..%ProcessResult($$$OK, info)
}

ClassMethod Ping() As %Status
{
  SET pong = {
    "message": "ping"
  }
  QUIT ..%ProcessResult($$$OK, pong)
}

ClassMethod CheckDebug() As %Boolean
{
  If ('$LISTFIND($LISTFROMSTRING($ROLES), "%All")) {
    Return 0
  }
  If (%request.GetCgiEnv("HTTP_REGISTRY_DEBUG")'=$SYSTEM.Util.GetEnviron("REGISTRY_DEBUG")) {
    Return 0
  }
  Return 1
}

ClassMethod Reset() As %Status
{
  If ('..CheckDebug()) {
    Return ..%ProcessResult(..#HTTP403FORBIDDEN)
  }

  Set sc = $$$OK

  Set tSC = ##class(Package).%KillExtent()
  Set sc = $$$ADDSC(sc, tSC)
  Set tSC = ##class(Package).%PurgeIndices()
  Set sc = $$$ADDSC(sc, tSC)

  QUIT ..%ProcessResult(sc)
}

ClassMethod Package(pkg As %String = "", version As %String = "") As %Status
{
  SET pkg = $$$lcase(pkg)
  set version = ##class(ZPM.Package).versionValidate(pkg, version)
  if (version="") {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  SET package = ##class(ZPM.Package).%OpenId(pkg_"||"_version)
  IF '$isobject(package) {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  
  RETURN ..%ProcessResult($$$OK, package)
}

ClassMethod PackageManifest(pkg As %String = "", version As %String = "") As %Status
{
  SET pkg = $$$lcase(pkg)  
  set version = ##class(ZPM.Package).versionValidate(pkg, version)
  if (version="") {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  SET package = ##class(ZPM.Package).%OpenId(pkg_"||"_version)
  IF '$isobject(package) {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  
  If package.manifest.Size {
    Set %response.ContentType = "text/xml"
    RETURN ..%ProcessResult($$$OK, package.manifest)
  }
  RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
}

ClassMethod PackageInstaller(pkg As %String = "", version As %String = "") As %Status
{
  SET pkg = $$$lcase(pkg)  
  set version = ##class(ZPM.Package).versionValidate(pkg, version)
  if (version="") {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  SET package = ##class(ZPM.Package).%OpenId(pkg_"||"_version)
  IF '$isobject(package) {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  
  If package.installer.Size {
    Set filename = pkg_"-"_version_".xml"
    Set %response.ContentType = "text/xml"
    Do %response.SetHeader("Content-Disposition", "attachment; filename="""_filename_"""")
    RETURN ..%ProcessResult($$$OK, package.installer)
  }
  RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
}

ClassMethod PublishPackage() As %Status
{
  If ($USERNAME="UnknownUser") {
    RETURN ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED)
  }
  If (%request.ContentType '= ..#CONTENTTYPEJSON) {    
    RETURN ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
  }
  
  set package = ##class(ZPM.Package).%New() 
  $$$ThrowOnError(package.%JSONImport(%request.Content))
  
  do ##class(ZPM.Package).NameVersionDelete(package.name, package.version)
  $$$ThrowOnError(package.%Save())
    
  Return ..Package(package.name, package.version)
}

ClassMethod UpdatePackage() As %Status
{
  If (%request.ContentType '= ..#CONTENTTYPEJSON) {    
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
  }
  Return ##class(ZPM.Package).UpdatePackage(%request.Content)
}

ClassMethod GetArchive(pkg, fileName) As %Status
{
  SET version = $PIECE($PIECE(fileName, ".tgz", 1), pkg _ "-", 2, *)

  SET package = ##class(ZPM.Package).%OpenId(pkg _ "||" _ version)
  IF '$isobject(package) {
    RETURN ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  Do ##class(ZPM.Analytics.Event).SaveEvent("download", %request.GetCgiEnv("REMOTE_ADDR"), {"name":(package.name),"version":(package.version)})
  Set token = ##class(%PopulateUtils).StringMin(16,16)
  Set ^IRIS.TempZPMRInst(token) = $Listbuild(pkg, version)
  Do %response.SetHeader("INSTALLTOKEN",token)

  SET tStream = package.package
  SET %response.NoCharSetConvert = 1
  SET %response.CharSet = "RAW"
  SET %response.ContentType = "application/tar+gzip"

  RETURN ..%ProcessResult($$$OK, tStream)
}

ClassMethod AllPackages() As %Status
{
  Set tList = []
  
  Set tRS = ##class(ZPM.Package).ListLatestFunc()
  If (tRS.%SQLCODE=-99) {
    return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN)
  }
  While tRS.%Next() {
    Set tPkgInfo = {
      "name": (tRS.name),
      "repository": (tRS.repository),
      "versions": [(tRS.version)]
    }
    do tList.%Push(tPkgInfo)
  }
  
  RETURN ..%ProcessResult($$$OK, tList)
}

ClassMethod CollectAnalytics(action As %String = "") As %Status
{
  If (%request.ContentType '= ..#CONTENTTYPEJSON) {    
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
  }
  If (action = "") {    
    Return ..ReportHttpStatusCode(HTTP404NOTFOUND)
  }
  Set token = %request.GetCgiEnv("HTTP_INSTALLTOKEN")
  If token'="", $Data(^IRIS.TempZPMRInst(token)) {
    Kill ^IRIS.TempZPMRInst(token)
    Return ##class(ZPM.Analytics.Event).SaveEvent(action, %request.GetCgiEnv("REMOTE_ADDR"), %request.Content)
  } 
  Return $$$ERROR(5001, "Invalid token")
}

}
