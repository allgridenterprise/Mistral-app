# Opprett en ny DocumentView for å håndtere dokumenter
@'
<UserControl x:Class="MistralApp.Views.DocumentView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
             xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
             mc:Ignorable="d">
    
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Verktøylinje -->
        <ToolBar Grid.Row="0">
            <Button Command="{Binding ImportDocumentCommand}">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="📄 " FontSize="16"/>
                    <TextBlock Text="Importer dokument" Margin="5,0,0,0"/>
                </StackPanel>
            </Button>
            
            <Separator/>
            
            <Button Command="{Binding AnalyzeDocumentCommand}" 
                    IsEnabled="{Binding HasSelectedDocument}">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="🔍 " FontSize="16"/>
                    <TextBlock Text="Analyser" Margin="5,0,0,0"/>
                </StackPanel>
            </Button>
        </ToolBar>

        <!-- Dokumentliste og detaljer -->
        <Grid Grid.Row="1" Margin="0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="300"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Dokumentliste -->
            <DockPanel Grid.Column="0">
                <TextBox DockPanel.Dock="Top" 
                         Text="{Binding SearchText, UpdateSourceTrigger=PropertyChanged}"
                         Margin="0,0,0,5"
                         Padding="5"
                         PlaceholderText="Søk i dokumenter..."/>
                
                <ListBox ItemsSource="{Binding Documents}"
                         SelectedItem="{Binding SelectedDocument}">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <StackPanel>
                                <TextBlock Text="{Binding DocumentType}" 
                                         FontWeight="Bold"/>
                                <TextBlock Text="{Binding FilePath}" 
                                         TextTrimming="CharacterEllipsis"/>
                            </StackPanel>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
            </DockPanel>

            <!-- Dokumentdetaljer -->
            <DockPanel Grid.Column="1" Margin="10,0,0,0">
                <GroupBox Header="Dokumentdetaljer" DockPanel.Dock="Top">
                    <Grid Margin="5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Grid.Column="0" Text="ID:" Margin="0,0,10,5"/>
                        <TextBlock Grid.Row="0" Grid.Column="1" Text="{Binding SelectedDocument.Id}"/>

                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Type:" Margin="0,0,10,5"/>
                        <TextBlock Grid.Row="1" Grid.Column="1" Text="{Binding SelectedDocument.DocumentType}"/>

                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Status:" Margin="0,0,10,5"/>
                        <TextBlock Grid.Row="2" Grid.Column="1" Text="{Binding SelectedDocument.Status}"/>

                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Opprettet:" Margin="0,0,10,5"/>
                        <TextBlock Grid.Row="3" Grid.Column="1" Text="{Binding SelectedDocument.Created}"/>
                    </Grid>
                </GroupBox>

                <!-- Metadata og analyse -->
                <TabControl>
                    <TabItem Header="Metadata">
                        <DataGrid ItemsSource="{Binding SelectedDocumentMetadata}"
                                  AutoGenerateColumns="False"
                                  IsReadOnly="True">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Nøkkel" Binding="{Binding Key}"/>
                                <DataGridTextColumn Header="Verdi" Binding="{Binding Value}"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </TabItem>
                    <TabItem Header="Analyse">
                        <TextBox Text="{Binding SelectedDocumentAnalysis, Mode=OneWay}"
                                 IsReadOnly="True"
                                 TextWrapping="Wrap"
                                 AcceptsReturn="True"
                                 VerticalScrollBarVisibility="Auto"/>
                    </TabItem>
                </TabControl>
            </DockPanel>
        </Grid>

        <!-- Statuslinje -->
        <StatusBar Grid.Row="2">
            <StatusBarItem>
                <TextBlock Text="{Binding StatusMessage}"/>
            </StatusBarItem>
            <StatusBarItem HorizontalAlignment="Right">
                <ProgressBar Width="100" Height="15" 
                            IsIndeterminate="{Binding IsProcessing}"
                            Visibility="{Binding IsProcessing, Converter={StaticResource BooleanToVisibilityConverter}}"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</UserControl>
'@ | Out-File -FilePath "Views\DocumentView.xaml" -Encoding UTF8 -Force

# Opprett tilhørende ViewModel
@'
using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Threading.Tasks;
using System.Windows.Input;
using Microsoft.Win32;
using MistralApp.Models;
using MistralApp.Services;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace MistralApp.ViewModels
{
    public partial class DocumentViewModel : ObservableObject
    {
        private readonly WorkspaceManager _workspaceManager;
        private readonly DocumentService _documentService;

        public ObservableCollection<DocumentModel> Documents { get; } = new();

        [ObservableProperty]
        private DocumentModel? _selectedDocument;

        [ObservableProperty]
        private string _searchText = string.Empty;

        [ObservableProperty]
        private bool _isProcessing;

        [ObservableProperty]
        private string _statusMessage = "Klar";

        public bool HasSelectedDocument => SelectedDocument != null;

        public ObservableCollection<KeyValuePair<string, object>> SelectedDocumentMetadata { get; } = new();

        [ObservableProperty]
        private string _selectedDocumentAnalysis = string.Empty;

        public DocumentViewModel(WorkspaceManager workspaceManager, DocumentService documentService)
        {
            _workspaceManager = workspaceManager;
            _documentService = documentService;
        }

        [RelayCommand]
        private async Task ImportDocumentAsync()
        {
            var dialog = new OpenFileDialog
            {
                Filter = "Alle filer|*.*|PDF filer|*.pdf|Word dokumenter|*.doc;*.docx|Tekstfiler|*.txt",
                Multiselect = false
            };

            if (dialog.ShowDialog() == true)
            {
                IsProcessing = true;
                StatusMessage = "Importerer dokument...";

                try
                {
                    var document = await _workspaceManager.ProcessNewDocumentAsync(dialog.FileName);
                    Documents.Add(document);
                    SelectedDocument = document;
                    StatusMessage = "Dokument importert og analysert";
                }
                catch (Exception ex)
                {
                    StatusMessage = $"Feil ved import: {ex.Message}";
                }
                finally
                {
                    IsProcessing = false;
                }
            }
        }

        [RelayCommand]
        private async Task AnalyzeDocumentAsync()
        {
            if (SelectedDocument == null) return;

            IsProcessing = true;
            StatusMessage = "Analyserer dokument...";

            try
            {
                var document = await _workspaceManager.ProcessNewDocumentAsync(SelectedDocument.FilePath);
                var index = Documents.IndexOf(SelectedDocument);
                Documents[index] = document;
                SelectedDocument = document;
                StatusMessage = "Dokument analysert";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Feil ved analyse: {ex.Message}";
            }
            finally
            {
                IsProcessing = false;
            }
        }

        partial void OnSelectedDocumentChanged(DocumentModel? value)
        {
            if (value != null)
            {
                SelectedDocumentMetadata.Clear();
                foreach (var item in value.Metadata)
                {
                    SelectedDocumentMetadata.Add(item);
                }

                SelectedDocumentAnalysis = value.Metadata.TryGetValue("analysis", out var analysis) 
                    ? analysis?.ToString() ?? ""
                    : "Ingen analyse tilgjengelig";
            }
            else
            {
                SelectedDocumentMetadata.Clear();
                SelectedDocumentAnalysis = "";
            }

            OnPropertyChanged(nameof(HasSelectedDocument));
        }

        partial void OnSearchTextChanged(string value)
        {
            // Implementer søkefunksjonalitet her
        }
    }
}
'@ | Out-File -FilePath "ViewModels\DocumentViewModel.cs" -Encoding UTF8 -Force
