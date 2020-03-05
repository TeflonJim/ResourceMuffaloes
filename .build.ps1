#Requires -Module Indented.RimWorld

param (
    [ValidateSet('Major', 'Minor', 'Build')]
    [String]$ReleaseType = 'Build'
)

task Build @(
    'Setup'
    'UpdateLastVersion'
    'Clean'
    'CopyFramework'
    'SetPublishedItemID'
    'CreatePatches'
    'UpdateLeatherThingDefs'
    'UpdateAnimalThingDefs'
    'UpdatePawnKindDefs'
    'UpdateItemDefs'
    'UpdateVersion'
    'CreatePackage'
    'UpdateLocal'
)

filter ConvertTo-OrderedDictionary {
    $dictionary = [Ordered]@{}
    foreach ($name in $_.PSObject.Properties.Name) {
        $dictionary.$name = $_.$name
    }
    $dictionary
}

task Setup {
    $Global:buildInfo = [PSCustomObject]@{
        Name            = 'ResourceMuffaloes'
        PublishedFileID = '1818042854'
        Version         = $null
        RimWorldVersion = $rwVersion = Get-RWVersion
        Path            = [PSCustomObject]@{
            Build            = Join-Path -Path $psscriptroot -ChildPath 'build'
            Generated        = $generatedPath = Join-Path -Path $psscriptroot -ChildPath 'generated\ResourceMuffaloes'
            GeneratedVersion = Join-Path -Path $generatedPath -ChildPath $rwVersion.ShortVersion
            Source           = $source = Join-Path -Path $psscriptroot -ChildPath 'source'
            Template         = Join-Path -Path $source -ChildPath 'template'
            About            = Join-Path -Path $source -ChildPath 'About\About.xml'
        }
        Data            = [PSCustomObject]@{
            Muffaloes = Get-Content (Join-Path $psscriptroot 'muffaloes.json') |
                ConvertFrom-Json |
                ConvertTo-OrderedDictionary
        }
    }
    $path = Join-Path $psscriptroot 'source\About\Manifest.xml'
    $xDocument = [System.Xml.Linq.XDocument]::Load($path)
    $buildInfo.Version = [Version]$xDocument.Element('Manifest').Element('version').Value
}

task UpdateLastVersion {
    $aboutXml = [System.Xml.Linq.XDocument]::Load($buildInfo.Path.About)
    $supportedVersionsNode = $aboutXml.Element('ModMetaData').Element('supportedVersions')

    $supportedVersions = $supportedVersionsNode.Elements('li').Value -as [Version[]] | Sort-Object

    if ($buildInfo.RimWorldVersion.ShortVersion -notin $supportedVersions) {
        $lastVersion = $supportedVersions[-1]
        $path = Join-Path -Path $buildInfo.Path.Source -ChildPath $lastVersion

        if (-not (Test-Path $path)) {
            $contentToArchive = Join-Path -Path $buildInfo.Path.Generated -ChildPath $lastVersion

            if (Test-Path $contentToArchive) {
                Copy-Item -Path $contentToArchive -Destination $buildInfo.Path.Source -Recurse -Force
            }
        }

        $supportedVersionsNode.Add(
            [System.Xml.Linq.XElement]::new(
                [System.Xml.Linq.XElement]::new([System.Xml.Linq.XName]'li', $buildInfo.RimWorldVersion.ShortVersion)
            )
        )

        $aboutXml.Save($buildInfo.Path.About)
    }
}

task Clean {
    if (Test-Path $buildInfo.Path.Build) {
        Remove-Item $buildInfo.Path.Build -Recurse
    }
    if (Test-Path $buildInfo.Path.Generated) {
        Remove-Item $buildInfo.Path.Generated -Recurse
    }
    New-Item $buildInfo.Path.Build -ItemType Directory
    New-Item $buildInfo.Path.GeneratedVersion -ItemType Directory
}

task CopyFramework {
    Get-ChildItem -Path $buildInfo.Path.Source -Exclude template | Copy-Item -Destination $buildInfo.Path.Generated -Recurse
    Join-Path -Path $buildInfo.Path.Source -ChildPath 'template\*' | Copy-Item -Destination $buildInfo.Path.GeneratedVersion -Recurse
}

task SetPublishedItemID {
    if ($buildInfo.PublishedFileID) {
        Set-Content (Join-Path $buildInfo.Path.Generated 'About\PublishedFileId.txt') -Value $buildInfo.PublishedFileID
    }
}

task CreatePatches {
    $path = Join-Path $buildInfo.Path.GeneratedVersion 'Patches\template.xml'

    foreach ($colour in $buildInfo.Data.Muffaloes.Keys) {
        $muffalo = $buildInfo.Data.Muffaloes[$colour]

        if ($muffalo.IsPatch) {
            $patchPath = $path -replace 'template\.xml$', ('{0}MuffaloPatch.xml' -f $colour)
            Copy-Item $path -Destination $patchPath

            $xDocument = [System.Xml.Linq.XDocument]::Load($patchPath)
            $xDocument.Element('Patch').Element('Operation').Element('xpath').Value = 'Defs/ThingDef[defName="{0}"]' -f $colour
            $xDocument.Save($patchPath)
        }
    }

    Remove-Item $path
}

task UpdateLeatherThingDefs {
    $commonParams = @{
        Name    = 'Core\Leather_Bluefur'
        DefType = 'ThingDef'
    }
    foreach ($colour in $buildInfo.Data.Muffaloes.Keys) {
        $muffalo = $buildInfo.Data.Muffaloes[$colour]

        $params = @{
            NewName = 'Leather_{0}MuffaloFur' -f $colour
            Update  = @{
                description                            = "The furry pelt of a {0} muffalo. This leather has been enriched with {0}. Good at temperature regulation in cold climates." -f $colour.ToLower()
                label                                  = '{0} muffalo fur' -f $colour.ToLower()
                'graphicData.color'                    = $muffalo.colour
                'stuffProps.color'                     = $muffalo.colour
                'stuffProps.commonality'               = 0.005
                'statBases.MaxHitPoints'               = 60 * $muffalo.modifiers.LeatherMaxHitPoint
                'statBases.Mass'                       = 0.03 * $muffalo.modifiers.Mass
                'statBases.MarketValue'                = 2.1 * $muffalo.modifiers.MarketValue
                'statBases.StuffPower_Armor_Sharp'     = 0.81 * $muffalo.modifiers.ArmorSharp
                'statBases.StuffPower_Armor_Blunt'     = 0.24 * $muffalo.modifiers.ArmorBlunt
                'statBases.StuffPower_Armor_Heat'      = 1.5 * $muffalo.modifiers.ArmorHeat
                'statBases.StuffPower_Insulation_Cold' = 16 * $muffalo.modifiers.InsulationCold
                'statBases.StuffPower_Insulation_Heat' = 16 * $muffalo.modifiers.InsulationHeat
            }
        }

        if ($muffalo.IsPatch) {
            $path = Join-Path $buildInfo.Path.GeneratedVersion ('Patches\{0}MuffaloPatch.xml' -f $colour)

            $def = Copy-RWModDef @commonParams @params
            $xDocument = [System.Xml.Linq.XDocument]::Load($path)

            $element = ([System.Xml.Linq.XElement[]]$xDocument.Element('Patch').
                Element('Operation').
                Element('match').
                Element('operations').
                Elements('li'))[0].
                Element('value')
            $element.Add($def.Root)

            $xDocument.Save($path)
        } else {
            $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloLeather.xml'

            Copy-RWModDef @commonParams @params -SaveAs $path
        }
    }
}

task UpdateAnimalThingDefs {
    $commonParams = @{
        Name    = 'Core\Muffalo'
        DefType = 'ThingDef'
    }
    foreach ($colour in $buildInfo.Data.Muffaloes.Keys) {
        $muffalo = $buildInfo.Data.Muffaloes[$colour]

        $params = @{
            NewName = '{0}Muffalo' -f $colour
            Update  = @{
                description       = "A large herding herbivore descended from buffalo and adapted for both cold and warm environments. While enraged muffalo are deadly, tamed muffalo are quite docile and can be used as pack animals.\n\nThis muffalo has been genetically engineered to absorb trace amounts of {0} from the ground and water sources." -f $colour.ToLower()
                label             = '{0} muffalo' -f $colour.ToLower()
                'race.leatherDef' = 'Leather_{0}MuffaloFur' -f $colour
            }
        }

        if ($muffalo.IsPatch) {
            $path = Join-Path $buildInfo.Path.GeneratedVersion ('Patches\{0}MuffaloPatch.xml' -f $colour)

            $def = Copy-RWModDef @commonParams @params
            $xDocument = [System.Xml.Linq.XDocument]::Load($path)

            $element = ([System.Xml.Linq.XElement[]]$xDocument.Element('Patch').
                Element('Operation').
                Element('match').
                Element('operations').
                Elements('li'))[1].
                Element('value')
            $element.Add($def.Root)

            $xDocument.Save($path)
        } else {
            $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloAnimalThing.xml'

            Copy-RWModDef @commonParams @params -SaveAs $path
        }

        $xDocument = [System.Xml.Linq.XDocument]::Load($path)

        $xDocument.Descendants('ThingDef').Where{
            $_.Element('defName').Value -eq ('{0}Muffalo' -f $colour)
        }.ForEach{
            $_.Element('comps').Elements('li').Where{ $_.Attribute('Class').Value -eq 'CompProperties_Milkable' }.ForEach{
                $_.Element('milkDef').Value = '{0}{1}' -f @(
                    $muffalo.DefNamePrefix
                    $colour
                )
                $_.Element('milkAmount').Value = $muffalo.milkAmount
            }
            $_.Element('comps').Elements('li').Where{ $_.Attribute('Class').Value -eq 'CompProperties_Shearable' }.ForEach{
                $_.Element('woolDef').Value = '{0}{1}' -f @(
                    $muffalo.DefNamePrefix
                    $colour
                )
                $_.Element('woolAmount').Value = $muffalo.woolAmount
            }
        }

        $xDocument.Save($path)
    }
}

task UpdatePawnKindDefs {
    $commonParams = @{
        Name    = 'Core\Muffalo'
        DefType = 'PawnKindDef'
    }
    foreach ($colour in $buildInfo.Data.Muffaloes.Keys) {
        $muffalo = $buildInfo.Data.Muffaloes[$colour]

        $params = @{
            NewName = '{0}Muffalo' -f $colour
            Update  = @{
                label = '{0} muffalo' -f $colour.ToLower()
            }
        }

        if ($muffalo.IsPatch) {
            $path = Join-Path $buildInfo.Path.GeneratedVersion ('Patches\{0}MuffaloPatch.xml' -f $colour)

            $def = Copy-RWModDef @commonParams @params
            $xDocument = [System.Xml.Linq.XDocument]::Load($path)

            $element = ([System.Xml.Linq.XElement[]]$xDocument.Element('Patch').
                Element('Operation').
                Element('match').
                Element('operations').
                Elements('li'))[2].
                Element('value')
            $element.Add($def.Root)

            $xDocument.Save($path)
        } else {
            $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloPawnKind.xml'

            Copy-RWModDef @commonParams @params -SaveAs $path
        }

        $xDocument = [System.Xml.Linq.XDocument]::Load($path)

        $xDocument = [System.Xml.Linq.XDocument]::Load($path)

        $xDocument.Descendants('PawnKindDef').Where{
            $_.Element('defName').Value -eq ('{0}Muffalo' -f $colour)
        }.ForEach{
            $_.Attribute('Name').Value = $_.Element('defName').Value

            $lifeStage = $_.Element('lifeStages').Elements('li') | Select-Object -First 1
            $lifeStage.Element('label').Value = '{0} muffalo calf' -f $colour
            $lifeStage.Element('labelPlural').Value = '{0} muffalo calves' -f $colour

            $_.Descendants('bodyGraphicData').ForEach{
                $_.Element('texPath').Value = 'Muffalo/Muffalo'
                $_.Add(
                    [System.Xml.Linq.XElement]::new(
                        [System.Xml.Linq.XName]"color",
                        $muffalo.colour
                    )
                )
            }
        }

        $xDocument.Save($path)
    }
}

task UpdateItemDefs {
    $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloEgg.xml'

    $xDocument = [System.Xml.Linq.XDocument]::Load($path)
    $template = $xDocument.Root.Elements('ThingDef').Where( { $_.Element('defName').Value -eq 'Egg{0}MuffaloFertilized' } )[0]

    foreach ($colour in $buildInfo.Data.Muffaloes.Keys) {
        $muffalo = $buildInfo.Data.Muffaloes[$colour]

        $item = [System.Xml.Linq.XElement]::new(($template -f @(
            $colour
            $colour.ToLower()
            $muffalo.colour
        )))

        $item.Element('costList').Add(
            [System.Xml.Linq.XElement]::new(
                [System.Xml.Linq.XName]('{0}{1}' -f @(
                    $muffalo.DefNamePrefix
                    $colour
                )),
                100
            )
        )

        if ($muffalo.IsPatch) {
            $path = Join-Path $buildInfo.Path.GeneratedVersion ('Patches\{0}MuffaloPatch.xml' -f $colour)

            $xDocument = [System.Xml.Linq.XDocument]::Load($path)
            $element = ([System.Xml.Linq.XElement[]]$xDocument.Element('Patch').
                Element('Operation').
                Element('match').
                Element('operations').
                Elements('li'))[3].
                Element('value')
            $element.Add($item)
        } else {
            $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloEgg.xml'

            $xDocument = [System.Xml.Linq.XDocument]::Load($path)
            $xDocument.Root.Add($item)
        }

        $xDocument.Save($path)
    }

    $path = Join-Path $buildInfo.Path.GeneratedVersion 'Defs\ThingDefs\MuffaloEgg.xml'
    $xDocument = [System.Xml.Linq.XDocument]::Load($path)
    $xDocument.Root.Elements('ThingDef').Where( { $_.Element('defName').Value -eq 'Egg{0}MuffaloFertilized' } )[0].Remove()
    $xDocument.Save($path)
}

task UpdateVersion {
    $version = $buildInfo.Version
    $version = switch ($ReleaseType) {
        'Major' { [Version]::new($version.Major + 1, 0, 0) }
        'Minor' { [Version]::new($version.Major, $version.Minor + 1, 0) }
        'Build' { [Version]::new($version.Major, $version.Minor, $version.Build + 1) }
    }

    $path = Join-Path $psscriptroot 'source\About\Manifest.xml'
    $xDocument = [System.Xml.Linq.XDocument]::Load($path)
    $xDocument.Element('Manifest').Element('version').Value = $version
    $xDocument.Save($path)

    Copy-Item $path (Join-Path $buildInfo.Path.Generated 'About')
}

task CreatePackage {
    $params = @{
        Path            = $buildInfo.Path.Generated
        DestinationPath = Join-Path $buildInfo.Path.Build ('{0}.zip' -f $buildInfo.Name)
    }
    Compress-Archive @params
}

task UpdateLocal {
    $path = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 294100' -Name 'InstallLocation').InstallLocation
    $modPath = [System.IO.Path]::Combine($path, 'Mods', $buildInfo.Name)

    if (Test-Path $modPath) {
        Remove-Item $modPath -Recurse
    }

    Copy-Item $buildInfo.Path.Generated "$path\Mods" -Recurse -Force
}
