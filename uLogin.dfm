object frmLogin: TfrmLogin
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'PMDesk - Sign in'
  ClientHeight = 210
  ClientWidth = 420
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object lblServerCaption: TLabel
    Left = 16
    Top = 20
    Width = 32
    Height = 15
    Caption = 'Server'
  end
  object lblServer: TLabel
    Left = 96
    Top = 20
    Width = 5
    Height = 15
    Caption = '-'
  end
  object lblEmail: TLabel
    Left = 16
    Top = 56
    Width = 29
    Height = 15
    Caption = 'Email'
  end
  object lblPassword: TLabel
    Left = 16
    Top = 92
    Width = 50
    Height = 15
    Caption = 'Password'
  end
  object lblStatus: TLabel
    Left = 16
    Top = 124
    Width = 388
    Height = 36
    AutoSize = False
    WordWrap = True
  end
  object edtEmail: TEdit
    Left = 96
    Top = 52
    Width = 300
    Height = 23
    TabOrder = 0
  end
  object edtPassword: TEdit
    Left = 96
    Top = 88
    Width = 300
    Height = 23
    PasswordChar = '*'
    TabOrder = 1
  end
  object btnSignIn: TButton
    Left = 232
    Top = 168
    Width = 80
    Height = 25
    Caption = 'Sign in'
    Default = True
    TabOrder = 2
  end
  object btnCancel: TButton
    Left = 320
    Top = 168
    Width = 80
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end
