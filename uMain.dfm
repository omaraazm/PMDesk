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
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1184
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    ExplicitLeft = 512
    ExplicitTop = 360
    ExplicitWidth = 185
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
    ExplicitLeft = 16
    ExplicitTop = 16
    ExplicitHeight = 22
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
    ExplicitLeft = 592
    ExplicitTop = 8
    ExplicitWidth = 0
  end
  object mtProperties: TFDMemTable
    FetchOptions.AssignedValues = [evMode]
    FetchOptions.Mode = fmAll
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    UpdateOptions.AssignedValues = [uvCheckRequired, uvAutoCommitUpdates]
    UpdateOptions.CheckRequired = False
    UpdateOptions.AutoCommitUpdates = True
    Left = 824
    Top = 216
  end
  object dsProperties: TDataSource
    DataSet = mtProperties
    Left = 904
    Top = 224
  end
end
