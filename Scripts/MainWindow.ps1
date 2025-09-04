# Opprett hovedvinduet i XAML
@"
<Window x:Class="MistralApp.Views.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:viewmodels="clr-namespace:MistralApp.ViewModels"
        mc:Ignorable="d"
        Title="🎯 Mistral Suite" Height="600" Width="800"
        MinHeight="400" MinWidth="600">
    
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="Margin" Value="5"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="5"/>
            <Setter Property="Margin" Value="5"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="5"/>
            <Setter Property="Margin" Value="5"/>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <Border Grid.Row="0" Background="#2c3e50" Padding="10">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="🎯 Mistral Suite" Foreground="White" FontSize="24" VerticalAlignment="Center"/>
                <ComboBox Margin="20,0,0,0" Width="150" 
                          ItemsSource="{Binding AvailableModels}"
                          SelectedItem="{Binding SelectedModel}"/>
            </StackPanel>
        </Border>
        
        <!-- Main Content -->
        <Grid Grid.Row="1" Margin="10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Input -->
            <DockPanel Grid.Column="0">
                <TextBlock DockPanel.Dock="Top" Text="Prompt:" FontWeight="Bold"/>
                <TextBox AcceptsReturn="True" TextWrapping="Wrap" 
                         Text="{Binding Prompt, UpdateSourceTrigger=PropertyChanged}"/>
            </DockPanel>
            
            <!-- Buttons -->
            <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="5,0">
                <Button Command="{Binding SendPromptCommand}" 
                        IsEnabled="{Binding IsProcessing, Converter={StaticResource InverseBooleanConverter}}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Send" Margin="0,0,5,0"/>
                        <TextBlock Text="▶" FontWeight="Bold"/>
                    </StackPanel>
                </Button>
                <Button Command="{Binding ClearPromptCommand}" Margin="0,10,0,0">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Tøm" Margin="0,0,5,0"/>
                        <TextBlock Text="✕" FontWeight="Bold"/>
                    </StackPanel>
                </Button>
            </StackPanel>
            
            <!-- Output -->
            <DockPanel Grid.Column="2">
                <TextBlock DockPanel.Dock="Top" Text="Svar:" FontWeight="Bold"/>
                <TextBox IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" 
                         Text="{Binding Response, Mode=OneWay}"/>
            </DockPanel>
        </Grid>
        
        <!-- Status Bar -->
        <StatusBar Grid.Row="2">
            <StatusBarItem>
                <TextBlock Text="{Binding StatusMessage}"/>
            </StatusBarItem>
            <StatusBarItem HorizontalAlignment="Right">
                <ProgressBar Width="100" Height="15" IsIndeterminate="{Binding IsProcessing}" 
                             Visibility="{Binding IsProcessing, Converter={StaticResource BooleanToVisibilityConverter}}"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@ | Out-File -FilePath "Views\MainWindow.xaml" -Encoding UTF8

# Opprett code-behind for hovedvinduet
@"
using System.Windows;
using MistralApp.ViewModels;

namespace MistralApp.Views
{
    public partial class MainWindow : Window
    {
        public MainWindow(MainViewModel viewModel)
        {
            InitializeComponent();
            DataContext = viewModel;
        }
    }
}
"@ | Out-File -FilePath "Views\MainWindow.xaml.cs" -Encoding UTF8
