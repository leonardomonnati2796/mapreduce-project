$ErrorActionPreference = 'SilentlyContinue'
Write-Host '=== LOG LIVE CHECKPOINT REDUCE (premi Ctrl+C per uscire) ==='

$pattern = 'ReduceTask .*checkpoint|assegno con checkpoint|riassegno con checkpoint|Reset ReduceTask|timeout|worker morto|Assegnato ReduceTask|Riassegnato ReduceTask|ripresa da checkpoint|scritti .* record|CHECKPOINT TROVATO|saltate .* chiavi già processate|Preservato checkpoint|checkpoint salvato'

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


