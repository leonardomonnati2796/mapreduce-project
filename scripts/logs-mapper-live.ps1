$ErrorActionPreference = 'SilentlyContinue'
Write-Host '=== LOG LIVE MAPPER/RECOVERY (premi Ctrl+C per uscire) ==='

# Pattern per eventi rilevanti della fase Map e recovery
$pattern = 'MapTask|Assegnato MapTask|Riassegnato MapTask|timeout|worker morto|mapper|intermediate|spill'

docker-compose -f docker/docker-compose.yml logs -f master0 master1 master2 |
  Select-String -Pattern $pattern |
  ForEach-Object {
    if ($_ -match '^(?<svc>[^|]+)\s*\|\s*(?<msg>.*)$') {
      $svc = $matches['svc'].Trim()
      $msg = $matches['msg'] -replace '.*logger\.go:\d+:\s*',''
      Write-Host ("[$svc] $msg")
    } else {
      $_
    }
  }


