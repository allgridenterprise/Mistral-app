# Erstatt .csproj med den komplette versjonen
@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <OutputType>Exe</OutputType>
        <TargetFramework>net8.0</TargetFramework>
        <RootNamespace>Mistral_app</RootNamespace>
        <ImplicitUsings>enable</ImplicitUsings>
        <Nullable>enable</Nullable>
    </PropertyGroup>
    
    <ItemGroup>
      <PackageReference Include="Microsoft.Extensions.Configuration" Version="9.0.8" />
      <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="9.0.8" />
      <PackageReference Include="Microsoft.Extensions.Hosting" Version="9.0.8" />
      <PackageReference Include="Microsoft.Extensions.Http" Version="9.0.8" />
      <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
      <PackageReference Include="Python.Runtime" Version="2.7.9" />
    </ItemGroup>
</Project>
'@ | Set-Content "Mistral app.csproj"
