function Add-UIModule
{
    param(
    [Parameter(ParameterSetName='File',
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$true)]
    [string]
    $File,        
    
    [Parameter(ParameterSetName='Assembly',Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [string]
    $Assembly,    
    
    [Parameter(ParameterSetName='Type',
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    [Type]
    $Type,
    
    # The name of the module to create
    [string]
    $Name,        
    
    [switch]
    $OutputCode,
        
    [ScriptBlock]
    $On_ImportModule,
    
    [ScriptBlock]
    $On_RemoveModule
    )
    
    begin {
        $specificTypeNameWhiteList =
            'System.Windows.Input.ApplicationCommands',
            'System.Windows.Input.ComponentCommands',
            'System.Windows.Input.NavigationCommands',
            'System.Windows.Input.MediaCommands',
            'System.Windows.Documents.EditingCommands',
            'System.Windows.Input.CommandBinding'

        $specificTypeNameBlackList =
            'System.Windows.Threading.DispatcherFrame', 
            'System.Windows.DispatcherObject',
            'System.Windows.Interop.DocObjHost',
            'System.Windows.Ink.GestureRecognizer',
            'System.Windows.Data.XmlNamespaceMappingCollection',
            'System.Windows.Annotations.ContentLocator',
            'System.Windows.Annotations.ContentLocatorGroup'


    }
    
    process {
        $types = @()
        if ($psCmdlet.ParameterSetName -eq 'Type') 
        {
            $types+=$type
        } elseif ($psCmdlet.ParameterSetName -eq 'File') 
        {            
            $asm = [Reflection.Assembly]::LoadFrom($ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($file))
            if ($asm) {
                $types += $asm.GetTypes()
            }
        } elseif ($psCmdlet.ParameterSetName -eq 'Assembly') {
            try {
                $types += [Reflection.Assembly]::Load($assembly)
            } catch {
                $err = $_
                try {
                    [Reflection.Assembly]::LoadWithPartialName($assembly)
                } catch {
                    Write-Error $err                                     
                    Write-Error $_
                }
            }
        }
        
        $childId = Get-Random
        if ($types) {                    
            $resultList = New-Object Collections.arraylist 
            $typeCounter =0
            $count= @($types).Count

            $filteredTypes = $types | Where-Object {
                    $specificTypeNameWhiteList -contains $_.FullName -or
                    (
                        $_.IsPublic -and 
                        (-not $_.IsGenericType) -and 
                        (-not $_.IsAbstract) -and
                        (-not $_.IsEnum) -and
                        ($_.FullName -notlike "*Internal*") -and
                        (-not $_.IsSubclassOf([EventArgs])) -and
                        (-not $_.IsSubclassOf([Exception])) -and
                        (-not $_.IsSubclassOf([Attribute])) -and
                        (-not $_.IsSubclassOf([Windows.Markup.ValueSerializer])) -and
                        (-not $_.IsSubclassOf([MulticastDelegate])) -and
                        (-not $_.IsSubclassOf([ComponentModel.TypeConverter])) -and
                        (-not $_.GetInterface([Collections.ICollection])) -and
                        (-not $_.IsSubClassOf([Windows.SetterBase])) -and
                        (-not $_.IsSubclassOf([Security.CodeAccessPermission])) -and
                        (-not $_.IsSubclassOf([Windows.Media.ImageSource])) -and
        #               (-not $_.IsSubclassOf([Windows.Input.InputGesture])) -and
        #               (-not $_.IsSubclassOf([Windows.Input.InputBinding])) -and
                        (-not $_.IsSubclassOf([Windows.TemplateKey])) -and
                        (-not $_.IsSubclassOf([Windows.Media.Imaging.BitmapEncoder])) -and
                        ($_.BaseType -ne [Object]) -and
                        ($_.BaseType -ne [ValueType]) -and
                        $_.Name -notlike '*KeyFrame' -and
                        $specificTypeNameBlackList -notcontains $_.FullName
                    )
                }
            }

            $ofs = [Environment]::NewLine
            $count = $filteredTypes.Count
            foreach ($type in $filteredTypes) 
            {
                if (-not $type) { continue }
                $typeCounter++
                $perc = $typeCounter * 100/ $count 
                Write-Progress "Generating Code" $type.Fullname -PercentComplete $perc -Id $childId     
                $typeCode = ConvertFrom-TypeToScriptCmdlet -Type $type -ErrorAction SilentlyContinue -AsScript   
                
                $null = $resultList.Add("$typeCode")
            }            

            $resultList = $resultList | Where-Object { $_ }             
        
            $code = "$resultList"                   
            if ($outputCode) {
                $Code
            }
            
            
            
            if ($name.Contains("\")) {
                # It's definately a path
                $semiResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Name)
                if ($semiResolved -like "*.psd1") {
                    $outputDll = $false
                } elseif ($semiResolved -like "*.psm1") {
                    $Outputdll = $false
                    $realModulePath = $semiResolved.Replace(".psm1", ".psd1")
                } elseif ($semiResolved -like "*.dll") {
                    $outputdll = $true
                    $realModulePath = $semiResolved        
                } else {
                    $leaf = Split-Path -Path $semiResolved -Leaf 
                    $realModulePath = Join-Path $semiResolved "${leaf}.psd1" 
                }
                
            } elseif ($name -like "*.dll") {
                # It's a dll path, they want outputDll
                $OutputDll = $true
                $realModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($name)
            } elseif ($name -like "*.psd1") {
                # It's a manifest path, they don't want outputdll
                $Outputdll = $false
                $realModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($name)
            } elseif ($name -like ".psm1" ) {
                $Outputdll = $false
                $realModulePath = $realModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($name.Replace(".psm1",".psd1"))
            } else {
                # It's just a name, figure out what the real manifest path will be
                $realModulePath = "$env:UserProfile\Documents\WindowsPowerShell\Modules\$Name\$Name.psd1"
            }
            
            
            
            if ($outputDll) {
                $dllPath = $realModulePath
            } else {
                $dllPath = $realModulePath.Replace(".psd1",".dll")
            }
                        
                           
            <#
            
                Unfortunately, compiled code would add a lot of complexity here
                (some assemblies link only if they are installed with regasm, which would 
                get into selective elevation and open up a large can of worms.
                
                For the moment, this can be done with the script generator
            
            $addTypeParameters = @{
                TypeDefinition=$code
                IgnoreWarnings=$true
                ReferencedAssemblies=$types | 
                    Select-Object -ExpandProperty Assembly -Unique | 
                    ForEach-Object { @($_) + @($_.GetReferencedAssemblies()) | Select-Object -Unique } |
                    Where-Object { $_.Name -ne 'mscorlib' } |
                    ForEach-Object { if ($_.Location) { $_.Location } else { $_.Fullname } }
                Language='CSharpVersion3'
                OutputAssembly=$dllPath
                PassThru=$true                      
            }
            
            
            
            Add-Type @addTypeParameters
            #>
            $moduleroot = Split-Path $realmodulepath
            
            if (-not (Test-Path $moduleroot)) {
                New-Item -ItemType Directory -Path $moduleRoot | Out-Null
            }

            if ($outputDll) {
                return Get-Item $dllPath                
            }            
            
            # Ok, build the module scaffolding
            $dllLeaf = Split-Path $dllPath -Leaf
            $psm1Path  = $dllLeaf.Replace(".dll", ".psm1")   
            $absolutePsm1Path = Join-Path $moduleRoot $psm1Path
                     
@"
@{
    ModuleVersion = '1.0'
    RequiredModules = 'ShowUI'
    ModuleToProcess = '$psm1Path'
    GUID = '$([GUID]::NewGuid())'
}
"@ | 
    Set-Content -Path $realmodulePath -Encoding Unicode    
"
$On_ImportModule

$code

`$myInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    $On_RemoveModule
}
" |
    Set-Content -Path $absolutePsm1Path -Encoding Unicode
            
    }    
} 
