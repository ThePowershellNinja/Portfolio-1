
# Here is a reference that walks you through the basic multithreading process
# https://adamtheautomator.com/powershell-multithreading/
 
function verb-noun {
    
    param (

        # This is just an example parameter and should be replaced with a value that is unique to each job that the job can iterate on
        [string[]]$ComputerName,

        # Passing a parameter for max number of jobs that can run at one time for the user to configure at the time of execution
        [int]$MaxThreads = 64,

        # Passing a parameter for timeout of individual job threads (in seconds) for the user to configure at the time of execution
        [int]$ThreadTimeout = 300
    )

    begin {

        # Speficy the bulk of your per-job actions within this script block.
        # Please note that different executions of this scriptblock cannot communicate with eachother without a syncronized hashtable passed as an arguement
        $command = {
            Param(
                $Computer
            )

            # Most of the Command will go here
            Write-Output $Computer
        }
        
        # Specification for the amount of threads to use put in as a parameter by the user to set the thread count at runtime.
        $runspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxThreads)
        $runspacePool.open()

        # ArrayList to hold all of the threads
        $jobs = [Collections.ArrayList]@()
    }

    process {

        foreach ($computer in $ComputerName){

            # Progress bar for the creation of the threads. This can be modified to reflect what the function is doing.
            Write-Progress -Activity "Multithreading" -Status "Starting threads ($(@($jobs).count + 1)/$(@($ComputerName).count))"

            # This is the actual creation of each thread. Additional arguments should be added to this line if any more are needed by adding ".AddArgument($Argument)" statements to the end of the line with no spaces.
            $powershellThread = [powershell]::Create().AddScript($command).AddArgument($computer)

            # This is where the new thread is assigned to the runspace pool
            $powershellThread.RunspacePool = $runspacePool

            # Storing information about the thread. Handle, Thread, and StartTime values are mandatory here, but other values can be added in as you see fit.
            $null = $jobs.Add([PSCustomObject]@{
                # This is where the job will actually begin to execute.
                Handle       = $powershellThread.BeginInvoke()
                Thread       = $powershellThread
                StartTime    = [DateTime]::Now
                ComputerName = $computer
            })
        }
    }

    end {

        # While statement will keep running until all of the job results are returned
        while (@($jobs | Where-Object {$null -ne $_}).Count -gt 0) {

            # Progress Bar detailing remaining jobs. This can be modified to reflect what the function is doing
            Write-Progress -Activity "Multithreading" -Status "Waiting for $(@($Jobs | Where-Object {$null -ne $_}).Count) threads to finish"

            for ($i=0; $i -lt $jobs.count; $i++) {
                
                if ($jobs[$i]) {

                    if ($jobs[$i].Handle.IsCompleted) {

                        # EndInvoke is where we stop the thread from running and get the standard out results returned to us.
                        $jobs[$i].Thread.EndInvoke($jobs[$i].Handle)

                        # This is where we capture all of the errors from inside the thread and spit them out to the main console
                        foreach ($scriptError in $jobs[$i].Thread.Streams.Error) {
                        
                            $scriptErrorMessage = '{0}: {1}' -f $jobs[$i].Computername, $scriptError.Exception
                            Write-Error $scriptErrorMessage
                        }

                        # This is where we capture all of the warnings from inside the thread and spit them out to the main console
                        # There are more streams that you can capture, but I am only giving examples for the error stream and the warning stream
                        foreach ($scriptWarning in $jobs[$i].Thread.Streams.Warning) {

                            $scriptWarningMessage = '{0} - {1}' -f $jobs[$i].Computername, $scriptWarning.Message
                            Write-Warning $scriptWarningMessage
                        }

                        # Make sure the thread is cleaned up and nullified in the jobs array
                        $jobs[$i].Thread.Dispose()
                        $jobs[$i] = $null
                    }
                    elseif ($ThreadTimeout -ne 0 -and ([DateTime]::Now - $jobs[$i].StartTime).TotalSeconds -gt $ThreadTimeout) {

                        # The elasped time has been reached for the unresponsive thread and we are going to shut the thread down and return a timeout error
                        $timeoutErrorMessage = 'Thread timout for {0}' -f $jobs[$i].Computername
                        Write-Error $timeoutErrorMessage
    
                        $jobs[$i].Thread.Dispose()
                        $jobs[$i] = $null
                    }
                }
            }

            # We want to put a 1 second wait in our loop so that it doesnt run as fast as it possibly can and consume cpu
            Start-Sleep -Seconds 1
        }

        # Closing Progress Bar
        Write-Progress -Activity "Multithreading" -Completed

        # Necessary statements to ensure the runspace pool is no longer running in the background in Powershell.
        $RunspacePool.Close()
        $RunspacePool.Dispose()
    }
}