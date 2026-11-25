# تشخيصٌ مؤقّت: عميل UI Automation كأدوات ويندوز (لوحة اللمس، خدمات الإدخال، قارئ الشاشة) — يقرأ الحقل المركَّز
# ونصّه وتحديده كلّ 150ms أثناء الكتابة، فيُفعِّل إمكانيّة الوصول في فلاتر كما على حاسبات الوكلاء.
param([string]$Out = "uia_poll.log", [int]$Seconds = 900)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$deadline = (Get-Date).AddSeconds($Seconds)
$n = 0; $errs = 0; $text = 0
"start $(Get-Date -Format o)" | Out-File $Out -Encoding utf8
while ((Get-Date) -lt $deadline) {
  try {
    $f = [System.Windows.Automation.AutomationElement]::FocusedElement
    if ($f -ne $null) {
      $n++
      $pat = $null
      if ($f.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pat)) {
        $text++
        $doc = $pat.DocumentRange
        $t = $doc.GetText(-1)
        $sel = $pat.GetSelection()
        if ($sel.Length -gt 0) {
          $r = $sel[0].Clone()
          [void]$r.ExpandToEnclosingUnit([System.Windows.Automation.Text.TextUnit]::Word)
          $w = $r.GetText(-1)
          [void]$r.Move([System.Windows.Automation.Text.TextUnit]::Character, -2)
        }
        if ($text % 25 -eq 1) { "text n=$text len=$($t.Length) sel=$($sel.Length)" | Out-File $Out -Append -Encoding utf8 }
      } else {
        $vp = $null
        if ($f.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $v = $vp.Current.Value }
        if ($n % 50 -eq 1) { "focused n=$n class=$($f.Current.ClassName) type=$($f.Current.ControlType.ProgrammaticName)" | Out-File $Out -Append -Encoding utf8 }
      }
    }
  } catch {
    $errs++
    if ($errs -le 40) { "err: $($_.Exception.GetType().Name): $($_.Exception.Message)" | Out-File $Out -Append -Encoding utf8 }
  }
  Start-Sleep -Milliseconds 150
}
"end n=$n text=$text errs=$errs" | Out-File $Out -Append -Encoding utf8
