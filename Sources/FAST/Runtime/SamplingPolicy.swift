/**

  A sampling policy decides whether or not a sampling function should be
  called when the application has processed an input.

*/

public protocol SamplingPolicy {
    /** Initialize policy with sampling function. */
    func registerSampler(_ sample: @escaping () -> Void) -> Void

    /** Called by the runtime every time application processes an input, giving the policy
        the chance to call the sample function that was passed to registerSampler */
    func reportProgress(_ progress: UInt32) -> Void
}
