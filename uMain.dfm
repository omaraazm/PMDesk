object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'PMDesk'
  ClientHeight = 721
  ClientWidth = 1184
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object splLeft: TSplitter
    Left = 420
    Top = 41
    Height = 661
    ExplicitLeft = 600
    ExplicitTop = 328
    ExplicitHeight = 100
  end
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1184
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    ExplicitWidth = 1182
    object lblUser: TLabel
      Left = 190
      Top = 12
      Width = 71
      Height = 15
      Caption = 'Not signed in'
    end
    object btnRefresh: TButton
      Left = 8
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Refresh'
      TabOrder = 0
      OnClick = btnRefreshClick
    end
    object btnSignOut: TButton
      Left = 96
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Sign out'
      TabOrder = 1
      OnClick = btnSignOutClick
    end
  end
  object pnlProperties: TPanel
    Left = 0
    Top = 41
    Width = 420
    Height = 661
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    ExplicitHeight = 653
    object grdProperties: TDBGrid
      Left = 0
      Top = 0
      Width = 420
      Height = 661
      Align = alClient
      DataSource = dsProperties
      Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
      ReadOnly = True
      TabOrder = 0
      TitleFont.Charset = DEFAULT_CHARSET
      TitleFont.Color = clWindowText
      TitleFont.Height = -12
      TitleFont.Name = 'Segoe UI'
      TitleFont.Style = []
    end
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 702
    Width = 1184
    Height = 19
    Panels = <>
    SimplePanel = True
    ExplicitTop = 694
    ExplicitWidth = 1182
  end
  object pgcMain: TPageControl
    Left = 423
    Top = 41
    Width = 761
    Height = 661
    ActivePage = tsUnits
    Align = alClient
    TabOrder = 3
    object tsUnits: TTabSheet
      Caption = 'Units and Leases'
      object gbUnits: TGroupBox
        Left = 0
        Top = 0
        Width = 753
        Height = 170
        Align = alTop
        Caption = 'Units'
        TabOrder = 0
        object grdUnits: TDBGrid
          Left = 2
          Top = 17
          Width = 749
          Height = 151
          Align = alClient
          DataSource = dsUnits
          Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
          ReadOnly = True
          TabOrder = 0
          TitleFont.Charset = DEFAULT_CHARSET
          TitleFont.Color = clWindowText
          TitleFont.Height = -12
          TitleFont.Name = 'Segoe UI'
          TitleFont.Style = []
        end
      end
      object gbLeases: TGroupBox
        Left = 0
        Top = 170
        Width = 753
        Height = 140
        Align = alTop
        Caption = 'Leases'
        TabOrder = 1
        ExplicitLeft = 288
        ExplicitTop = 264
        ExplicitWidth = 185
        object grdLeases: TDBGrid
          Left = 2
          Top = 17
          Width = 749
          Height = 121
          Align = alClient
          DataSource = dsLeases
          Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
          ReadOnly = True
          TabOrder = 0
          TitleFont.Charset = DEFAULT_CHARSET
          TitleFont.Color = clWindowText
          TitleFont.Height = -12
          TitleFont.Name = 'Segoe UI'
          TitleFont.Style = []
        end
      end
      object gbPayments: TGroupBox
        Left = 0
        Top = 310
        Width = 753
        Height = 321
        Align = alClient
        Caption = 'Payments'
        TabOrder = 2
        ExplicitLeft = 288
        ExplicitTop = 264
        ExplicitWidth = 185
        ExplicitHeight = 105
        object pnlPaymentActions: TPanel
          Left = 2
          Top = 278
          Width = 749
          Height = 41
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 0
          ExplicitLeft = 288
          ExplicitTop = 144
          ExplicitWidth = 185
          object lblTotals: TLabel
            Left = 232
            Top = 12
            Width = 3
            Height = 15
          end
          object btnMarkPaid: TButton
            Left = 8
            Top = 8
            Width = 100
            Height = 25
            Caption = 'Mark paid'
            Enabled = False
            TabOrder = 0
          end
          object btnMarkUnpaid: TButton
            Left = 116
            Top = 8
            Width = 100
            Height = 25
            Caption = 'Mark unpaid'
            Enabled = False
            TabOrder = 1
          end
        end
        object grdPayments: TDBGrid
          Left = 2
          Top = 17
          Width = 749
          Height = 261
          Align = alClient
          DataSource = dsPayments
          Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
          ReadOnly = True
          TabOrder = 1
          TitleFont.Charset = DEFAULT_CHARSET
          TitleFont.Color = clWindowText
          TitleFont.Height = -12
          TitleFont.Name = 'Segoe UI'
          TitleFont.Style = []
        end
      end
    end
    object tsLoans: TTabSheet
      Caption = 'Loans'
      ImageIndex = 1
      object gbLoans: TGroupBox
        Left = 0
        Top = 0
        Width = 753
        Height = 150
        Align = alTop
        Caption = 'Loans'
        TabOrder = 0
        ExplicitLeft = 288
        ExplicitTop = 264
        ExplicitWidth = 185
        object grdLoans: TDBGrid
          Left = 2
          Top = 17
          Width = 749
          Height = 131
          Align = alClient
          DataSource = dsLoans
          Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
          ReadOnly = True
          TabOrder = 0
          TitleFont.Charset = DEFAULT_CHARSET
          TitleFont.Color = clWindowText
          TitleFont.Height = -12
          TitleFont.Name = 'Segoe UI'
          TitleFont.Style = []
        end
      end
      object gbSchedule: TGroupBox
        Left = 0
        Top = 150
        Width = 753
        Height = 481
        Align = alClient
        Caption = 'Schedule'
        TabOrder = 1
        ExplicitLeft = 288
        ExplicitTop = 264
        ExplicitWidth = 185
        ExplicitHeight = 105
        object pnlScheduleSummary: TPanel
          Left = 2
          Top = 446
          Width = 749
          Height = 33
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 0
          ExplicitTop = 438
          object lblSchedule: TLabel
            Left = 8
            Top = 8
            Width = 3
            Height = 15
          end
        end
        object grdSchedule: TDBGrid
          Left = 2
          Top = 17
          Width = 749
          Height = 429
          Align = alClient
          DataSource = dsSchedule
          Options = [dgTitles, dgIndicator, dgColumnResize, dgColLines, dgRowLines, dgTabs, dgRowSelect, dgAlwaysShowSelection, dgConfirmDelete, dgCancelOnExit, dgTitleClick, dgTitleHotTrack]
          ReadOnly = True
          TabOrder = 1
          TitleFont.Charset = DEFAULT_CHARSET
          TitleFont.Color = clWindowText
          TitleFont.Height = -12
          TitleFont.Name = 'Segoe UI'
          TitleFont.Style = []
        end
      end
    end
  end
  object mtProperties: TFDMemTable
    AfterScroll = mtPropertiesAfterScroll
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 264
  end
  object dsProperties: TDataSource
    DataSet = mtProperties
    Left = 680
    Top = 272
  end
  object mtUnits: TFDMemTable
    AfterScroll = mtUnitsAfterScroll
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 368
  end
  object mtLeases: TFDMemTable
    AfterScroll = mtLeasesAfterScroll
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 320
  end
  object mtPayments: TFDMemTable
    AfterScroll = mtPaymentsAfterScroll
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 496
  end
  object mtLoans: TFDMemTable
    AfterScroll = mtLoansAfterScroll
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 560
  end
  object mtSchedule: TFDMemTable
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 584
    Top = 432
  end
  object dsLeases: TDataSource
    DataSet = mtLeases
    Left = 688
    Top = 328
  end
  object dsUnits: TDataSource
    DataSet = mtUnits
    Left = 688
    Top = 384
  end
  object dsSchedule: TDataSource
    DataSet = mtSchedule
    Left = 688
    Top = 456
  end
  object dsPayments: TDataSource
    DataSet = mtPayments
    Left = 680
    Top = 520
  end
  object dsLoans: TDataSource
    DataSet = mtLoans
    Left = 680
    Top = 584
  end
end
