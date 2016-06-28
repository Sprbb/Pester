function Describe {
<#
.SYNOPSIS
Creates a logical group of tests.  All Mocks and TestDrive contents
defined within a Describe block are scoped to that Describe; they
will no longer be present when the Describe block exits.  A Describe
block may contain any number of Context and It blocks.

.PARAMETER Name
The name of the test group. This is often an expressive phrase describing the scenario being tested.

.PARAMETER Fixture
The actual test script. If you are following the AAA pattern (Arrange-Act-Assert), this
typically holds the arrange and act sections. The Asserts will also lie in this block but are
typically nested each in its own It block. Assertions are typically performed by the Should
command within the It blocks.

.PARAMETER Tag
Optional parameter containing an array of strings.  When calling Invoke-Pester, it is possible to
specify a -Tag parameter which will only execute Describe blocks containing the same Tag.

.EXAMPLE
function Add-Numbers($a, $b) {
    return $a + $b
}

Describe "Add-Numbers" {
    It "adds positive numbers" {
        $sum = Add-Numbers 2 3
        $sum | Should Be 5
    }

    It "adds negative numbers" {
        $sum = Add-Numbers (-2) (-2)
        $sum | Should Be (-4)
    }

    It "adds one negative number to positive number" {
        $sum = Add-Numbers (-2) 2
        $sum | Should Be 0
    }

    It "concatenates strings if given strings" {
        $sum = Add-Numbers two three
        $sum | Should Be "twothree"
    }
}

.LINK
It
Context
Invoke-Pester
about_Should
about_Mocking
about_TestDrive

#>

    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Name,

        [Alias('Tags')]
        $Tag=@(),

        [Parameter(Position = 1)]
        [ValidateNotNull()]
        [ScriptBlock] $Fixture = $(Throw "No test script block is provided. (Have you put the open curly brace on the next line?)")
    )

    if ($null -eq (& $SafeCommands['Get-Variable'] -Name Pester -ValueOnly -ErrorAction $script:IgnoreErrorPreference))
    {
        # User has executed a test script directly instead of calling Invoke-Pester
        $Pester = New-PesterState -Path (& $SafeCommands['Resolve-Path'] .) -TestNameFilter $null -TagFilter @() -SessionState $PSCmdlet.SessionState
        $script:mockTable = @{}
    }

    DescribeImpl @PSBoundParameters -Pester $Pester -DescribeOutputBlock ${function:Write-Describe} -TestOutputBlock ${function:Write-PesterResult}
}

function DescribeImpl {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Name,

        [Alias('Tags')]
        $Tag=@(),

        [Parameter(Position = 1)]
        [ValidateNotNull()]
        [ScriptBlock] $Fixture = $(Throw "No test script block is provided. (Have you put the open curly brace on the next line?)"),

        $Pester,

        [scriptblock] $DescribeOutputBlock,

        [scriptblock] $TestOutputBlock
    )

    if($Pester.TestNameFilter-and -not ($Pester.TestNameFilter | & $SafeCommands['Where-Object'] { $Name -like $_ }))
    {
        #skip this test
        return
    }

    if($Pester.TagFilter -and @(& $SafeCommands['Compare-Object'] $Tag $Pester.TagFilter -IncludeEqual -ExcludeDifferent).count -eq 0) {return}
    if($Pester.ExcludeTagFilter -and @(& $SafeCommands['Compare-Object'] $Tag $Pester.ExcludeTagFilter -IncludeEqual -ExcludeDifferent).count -gt 0) {return}

    $Pester.EnterTestGroup($Name, 'Describe')

    if ($null -ne $DescribeOutputBlock)
    {
        & $DescribeOutputBlock $Name
    }

    # If we're unit testing Describe, we have to restore the original PSDrive when we're done here;
    # this doesn't affect normal client code, who can't nest Describes anyway.
    $oldTestDrive = $null
    if (Test-Path TestDrive:\)
    {
        $oldTestDrive = (Get-PSDrive TestDrive).Root
    }

    try
    {
        New-TestDrive
        $testDriveAdded = $true

        Add-SetupAndTeardown -ScriptBlock $Fixture
        Invoke-TestGroupSetupBlocks

        do
        {
            $null = & $Fixture
        } until ($true)
    }
    catch
    {
        $firstStackTraceLine = $_.InvocationInfo.PositionMessage.Trim() -split '\r?\n' | & $SafeCommands['Select-Object'] -First 1
        $Pester.AddTestResult('Error occurred in Describe block', "Failed", $null, $_.Exception.Message, $firstStackTraceLine, $null, $null, $_)
        if ($null -ne $TestOutputBlock)
        {
            & $TestOutputBlock $Pester.TestResult[-1]
        }
    }
    finally
    {
        Invoke-TestGroupTeardownBlocks
        if ($testDriveAdded) { Remove-TestDrive }
    }

    Exit-MockScope

    if ($oldTestDrive)
    {
        New-TestDrive -Path $oldTestDrive
    }

    $Pester.LeaveTestGroup($Name, 'Describe')
}

# Name is now misleading; rename later.  (Many files touched to change this.)
function Assert-DescribeInProgress
{
    param ($CommandName)
    if ($null -eq $Pester)
    {
        throw "The $CommandName command may only be used from a Pester test script."
    }
}
