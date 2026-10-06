-- Kameň: skúška hladiny. Ľavý klik = kameň hodený do vody (vlnky sa rozbehnú od miesta dopadu), pravý = vibrácia.
-- To isté zvonka: pleamar --say goo "emit goo_kamen 512" (napr. okno po minimalizácii padne do lišty)
return {
    id = "kamen", nazov = "Kameň", ikona = "ripple", povaha = "pokojna", velkost = 22,
    klik = function(d) d:vlnka(9) end,
    pravy = function(d) d:vibruj(4) end,
    popis = function(d) return "ľavý: kameň do vody · pravý: vibrácia" end,
}
