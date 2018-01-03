/* Execute routine and update the progress counter. */
func executeAndReportProgress(_ m: MeasuringDevice, _ routine: (Void) -> Void) {
    routine()
    m.reportProgress()
}
